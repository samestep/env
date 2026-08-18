"""Shared helpers for driving the development Home Assistant.

The voice scripts all need the same few things: a REST call with the dev token,
a websocket command, audio as 16 kHz mono PCM, and a pipeline run that streams
audio in real time and reports when each stage finished.
"""
import asyncio, json, subprocess, time, urllib.request
import websockets

URL = "ws://127.0.0.1:8123/api/websocket"
TOKEN = open("scratch/hadev/token.txt").read().strip()
SR = 16000


def rest(path, body=None):
    req = urllib.request.Request(
        f"http://127.0.0.1:8123{path}",
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {TOKEN}"})
    return json.load(urllib.request.urlopen(req, timeout=120))


def ensure_whisper():
    """Point the dev instance at the faster-whisper running in this VM."""
    for e in rest("/api/config/config_entries/entry"):
        if e["domain"] == "wyoming":
            return
    flow = rest("/api/config/config_entries/flow",
                {"handler": "wyoming", "show_advanced_options": True})
    rest(f"/api/config/config_entries/flow/{flow['flow_id']}",
         {"host": "127.0.0.1", "port": 10300})


def pcm(path):
    return subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ar", str(SR),
                           "-ac", "1", "-f", "s16le", "-"],
                          capture_output=True, check=True).stdout


async def connect():
    ws = await websockets.connect(URL, max_size=None)
    await ws.recv()
    await ws.send(json.dumps({"type": "auth", "access_token": TOKEN}))
    assert json.loads(await ws.recv())["type"] == "auth_ok"
    return ws


_next_id = 0


def _ident():
    """Home Assistant requires websocket ids to increase, so hand them out here."""
    global _next_id
    _next_id += 1
    return _next_id


async def call(ws, **msg):
    ident = _ident()
    await ws.send(json.dumps({"id": ident, **msg}))
    while True:
        m = json.loads(await ws.recv())
        if m.get("id") == ident and m.get("type") == "result":
            if not m.get("success"):
                raise RuntimeError(f"{msg.get('type')} failed: {m.get('error')}")
            return m


async def pipeline_id(ws, name, **fields):
    """Find or create a pipeline by name, keeping its engines up to date."""
    pls = (await call(ws, type="assist_pipeline/pipeline/list"))["result"]["pipelines"]
    existing = next((p for p in pls if p.get("name") == name), None)
    if existing:
        stale = {k: v for k, v in fields.items() if existing.get(k) != v}
        if stale:
            await call(ws, type="assist_pipeline/pipeline/update",
                       pipeline_id=existing["id"],
                       **{k: v for k, v in existing.items() if k != "id"}, **stale)
        return existing["id"]
    res = await call(ws, type="assist_pipeline/pipeline/create",
                     name=name, language="en", conversation_language="en",
                     tts_engine=None, tts_language=None, tts_voice=None,
                     wake_word_entity=None, wake_word_id=None, **fields)
    return res["result"]["id"]


def engines():
    """The dev instance's speech-to-text and conversation entities."""
    states = rest("/api/states")
    stt = next(s["entity_id"] for s in states
               if s["entity_id"].startswith("stt.") and "demo" not in s["entity_id"])
    conv = next((s["entity_id"] for s in states
                 if s["entity_id"].startswith("conversation.") and "ollama" in s["entity_id"]),
                "conversation.home_assistant")
    return stt, conv


async def run(ws, pid, audio, end_stage="intent", trailing=4, **settings):
    """Stream audio in real time; return (ms from end of speech, text, reply, error)."""
    ident = _ident()
    stream = audio + b"\x00" * (SR * 2 * trailing)
    await ws.send(json.dumps({"id": ident, "type": "assist_pipeline/run",
                              "start_stage": "stt", "end_stage": end_stage,
                              "input": {"sample_rate": SR, **settings},
                              "pipeline": pid, "timeout": 60}))
    hid = None; task = None; marks = {}; audio_end = None; text = None; reply = ""

    async def pump():
        nonlocal audio_end
        for i in range(0, len(stream), 3200):
            await ws.send(bytes([hid]) + stream[i:i + 3200])
            if i <= len(audio) < i + 3200:
                audio_end = time.monotonic()
            await asyncio.sleep(0.1)

    while True:
        m = json.loads(await ws.recv())
        if m.get("id") != ident:
            continue
        if m.get("type") == "result" and not m.get("success"):
            return None, None, "", m.get("error")
        if m.get("type") != "event":
            continue
        e = m["event"]
        marks[e["type"]] = time.monotonic()
        if e["type"] == "run-start":
            hid = e["data"]["runner_data"]["stt_binary_handler_id"]
            task = asyncio.create_task(pump())
        if e["type"] == "stt-end":
            text = e["data"]["stt_output"]["text"]
        if e["type"] == "intent-end":
            reply = e["data"]["intent_output"]["response"]["speech"]["plain"]["speech"]
        if e["type"] in ("run-end", "error"):
            break
    if task:
        task.cancel()
    last = "intent-end" if end_stage == "intent" else "stt-end"
    if last not in marks or audio_end is None:
        return None, text, reply, f"no {last}"
    return (marks[last] - audio_end) * 1000, text, reply, None
