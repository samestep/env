"""End to end, old settings against new: audio in, answer out."""
import asyncio, json, statistics, subprocess, sys, time, urllib.request
sys.argv = sys.argv[:1]
exec(open("dev/turn-test.py").read().split("async def main")[0])

async def one(ws, ident, pid, audio, **settings):
    stream = audio + b"\x00" * (16000 * 2 * 4)
    await ws.send(json.dumps({"id": ident, "type": "assist_pipeline/run",
                              "start_stage": "stt", "end_stage": "intent",
                              "input": {"sample_rate": 16000, **settings},
                              "pipeline": pid, "timeout": 60}))
    hid = None; task = None; marks = {}; t_audio_end = None; reply = ""
    async def pump():
        nonlocal t_audio_end
        for i in range(0, len(stream), 3200):
            await ws.send(bytes([hid]) + stream[i:i + 3200])
            if i <= len(audio) < i + 3200:
                t_audio_end = time.monotonic()
            await asyncio.sleep(0.1)
    while True:
        m = json.loads(await ws.recv())
        if m.get("id") != ident: continue
        if m.get("type") == "result" and not m.get("success"):
            return None, m.get("error"), ""
        if m.get("type") != "event": continue
        e = m["event"]
        if e["type"] == "run-start":
            hid = e["data"]["runner_data"]["stt_binary_handler_id"]
            task = asyncio.create_task(pump())
        marks[e["type"]] = time.monotonic()
        if e["type"] == "intent-end":
            reply = e["data"]["intent_output"]["response"]["speech"]["plain"]["speech"]
        if e["type"] in ("run-end", "error"): break
    if task: task.cancel()
    if "intent-end" not in marks or t_audio_end is None:
        return None, "no intent-end", ""
    return (marks["intent-end"] - t_audio_end) * 1000, None, reply

async def main():
    ensure_whisper()
    ws = await websockets.connect(URL, max_size=None); await ws.recv()
    await ws.send(json.dumps({"type": "auth", "access_token": TOKEN}))
    assert json.loads(await ws.recv())["type"] == "auth_ok"
    states = rest("/api/states")
    stt = next(s["entity_id"] for s in states
               if s["entity_id"].startswith("stt.") and "demo" not in s["entity_id"])
    conv = next((s["entity_id"] for s in states
                 if s["entity_id"].startswith("conversation.") and "ollama" in s["entity_id"]),
                "conversation.home_assistant")
    pls = (await call(ws, 1, type="assist_pipeline/pipeline/list"))["result"]["pipelines"]
    p = next((x for x in pls if x.get("name") == "e2e"), None)
    if not p:
        res = await call(ws, 2, type="assist_pipeline/pipeline/create", name="e2e",
                         language="en", conversation_engine=conv, conversation_language="en",
                         stt_engine=stt, stt_language="en", tts_engine=None,
                         tts_language=None, tts_voice=None, wake_word_entity=None,
                         wake_word_id=None)
        pid = res["result"]["id"]
    else:
        pid = p["id"]
    print(f"conversation agent: {conv}\n")
    audio = pcm(sys.argv[1] if len(sys.argv) > 1 else "scratch/hadev/cmd.wav")
    ident = 400
    for label, s in (("before: silence 0.7, no turn model",
                      dict(silence_seconds=0.7, turn_detection=False)),
                     ("after:  silence 0.1, turn model",
                      dict(silence_seconds=0.1, turn_detection=True,
                           turn_threshold=0.9, turn_max_seconds=2.0))):
        runs = []
        for _ in range(3):
            ident += 1
            ms, err, reply = await one(ws, ident, pid, audio, **s)
            if err: print(f"  {label}: ERROR {err}"); break
            runs.append(ms)
            await asyncio.sleep(2)
        if runs:
            print(f"  {label:38} {statistics.median(runs):6.0f} ms   {reply[:40]!r}")

asyncio.run(main())
