"""Does turn detection stop the assistant cutting you off at a natural pause?

Streams a real recording in real time and reports what the pipeline heard before
deciding the turn was over. Speakers pause mid-sentence; with a short
silence_seconds the pipeline ends there and the transcript is truncated. The
turn model should recognise those pauses as unfinished and keep listening.

No artificial pause is inserted: the recording's own pauses are the test.

    dev/turn-test.py [audio] [seconds]
"""
import asyncio, json, subprocess, sys, time, urllib.request
import websockets

URL = "ws://127.0.0.1:8123/api/websocket"
TOKEN = open("scratch/hadev/token.txt").read().strip()
SR = 16000


def rest(path, body=None):
    req = urllib.request.Request(
        f"http://127.0.0.1:8123{path}",
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {TOKEN}"})
    return json.load(urllib.request.urlopen(req, timeout=60))


def ensure_whisper():
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


async def call(ws, ident, **msg):
    await ws.send(json.dumps({"id": ident, **msg}))
    while True:
        m = json.loads(await ws.recv())
        if m.get("id") == ident and m.get("type") == "result":
            return m


async def run(ws, ident, pipeline_id, audio, **settings):
    stream = audio + b"\x00" * (SR * 2 * 6)
    await ws.send(json.dumps({"id": ident, "type": "assist_pipeline/run",
                              "start_stage": "stt", "end_stage": "stt",
                              "input": {"sample_rate": SR, **settings},
                              "pipeline": pipeline_id, "timeout": 60}))
    hid = None; task = None; text = None; vad_end = None; t_audio = None
    async def pump():
        for i in range(0, len(stream), 3200):
            await ws.send(bytes([hid]) + stream[i:i + 3200])
            await asyncio.sleep(0.1)
    while True:
        m = json.loads(await ws.recv())
        if m.get("id") != ident:
            continue
        if m.get("type") == "result" and not m.get("success"):
            return None, None, m.get("error")
        if m.get("type") != "event":
            continue
        e = m["event"]
        if e["type"] == "run-start":
            hid = e["data"]["runner_data"]["stt_binary_handler_id"]
            t_audio = time.monotonic(); task = asyncio.create_task(pump())
        if e["type"] == "stt-vad-end":
            vad_end = time.monotonic() - t_audio
        if e["type"] == "stt-end":
            text = e["data"]["stt_output"]["text"]
        if e["type"] in ("run-end", "error"):
            break
    if task:
        task.cancel()
    return text, vad_end, None


async def main():
    ensure_whisper()
    await asyncio.sleep(2)
    path = sys.argv[1] if len(sys.argv) > 1 else "scratch/ha/jfk.wav"
    audio = pcm(path)
    if len(sys.argv) > 2:
        audio = audio[: SR * 2 * int(float(sys.argv[2]) * 1000) // 1000]
    ws = await websockets.connect(URL, max_size=None); await ws.recv()
    await ws.send(json.dumps({"type": "auth", "access_token": TOKEN}))
    assert json.loads(await ws.recv())["type"] == "auth_ok"

    states = rest("/api/states")
    stt = next((s["entity_id"] for s in states if s["entity_id"].startswith("stt.")
                and "demo" not in s["entity_id"]), None)
    pls = (await call(ws, 1, type="assist_pipeline/pipeline/list"))["result"]["pipelines"]
    existing = next((p for p in pls if p.get("name") == "turn-test"), None)
    if existing and existing.get("stt_engine") != stt:
        await call(ws, 2, type="assist_pipeline/pipeline/update",
                   pipeline_id=existing["id"],
                   **{k: v for k, v in existing.items() if k != "id"},
                   **{"stt_engine": stt, "stt_language": "en"})
        existing["stt_engine"] = stt
    if existing:
        pid = existing["id"]
    else:
        res = await call(ws, 3, type="assist_pipeline/pipeline/create", name="turn-test",
                         language="en", conversation_engine="conversation.home_assistant",
                         conversation_language="en", stt_engine=stt, stt_language="en",
                         tts_engine=None, tts_language=None, tts_voice=None,
                         wake_word_entity=None, wake_word_id=None)
        pid = res["result"]["id"]

    print(f"{path}, {len(audio)/2/SR:.1f} s of audio, stt={stt}\n")
    ident = 100
    for label, settings in (
        ("silence only, 0.25 s", dict(silence_seconds=0.25, turn_detection=False)),
        ("silence only, 0.70 s", dict(silence_seconds=0.70, turn_detection=False)),
        ("turn detection, 0.25 s", dict(silence_seconds=0.25, turn_detection=True,
                                        turn_threshold=0.9, turn_max_seconds=2.0)),
    ):
        ident += 1
        text, vad_end, err = await run(ws, ident, pid, audio, **settings)
        if err:
            print(f"  {label:24} ERROR {err}")
            continue
        print(f"  {label:24} ended {vad_end:5.1f}s  heard: {text!r}")
        await asyncio.sleep(1)

asyncio.run(main())
