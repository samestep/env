"""Where does the time go now? Per-stage, timed from the last sample of speech."""
import asyncio, json, statistics, sys, time
sys.path.insert(0, "dev")
from halib import SR, connect, engines, ensure_whisper, pcm, pipeline_id

async def one(ws, pid, audio, **settings):
    from halib import _ident
    ident = _ident()
    stream = audio + b"\x00" * (SR * 2 * 4)
    await ws.send(json.dumps({"id": ident, "type": "assist_pipeline/run",
                              "start_stage": "stt", "end_stage": "intent",
                              "input": {"sample_rate": SR, **settings},
                              "pipeline": pid, "timeout": 60}))
    hid = None; task = None; marks = {}; audio_end = None
    async def pump():
        nonlocal audio_end
        for i in range(0, len(stream), 3200):
            await ws.send(bytes([hid]) + stream[i:i + 3200])
            if i <= len(audio) < i + 3200:
                audio_end = time.monotonic()
            await asyncio.sleep(0.1)
    while True:
        m = json.loads(await ws.recv())
        if m.get("id") != ident: continue
        if m.get("type") != "event": continue
        e = m["event"]; marks[e["type"]] = time.monotonic()
        if e["type"] == "run-start":
            hid = e["data"]["runner_data"]["stt_binary_handler_id"]
            task = asyncio.create_task(pump())
        if e["type"] in ("run-end", "error"): break
    if task: task.cancel()
    if audio_end is None or "intent-end" not in marks: return None
    return {k: (v - audio_end) * 1000 for k, v in marks.items()}

async def main():
    ensure_whisper()
    ws = await connect(); stt, conv = engines()
    pid = await pipeline_id(ws, "e2e", stt_engine=stt, stt_language="en",
                            conversation_engine=conv)
    audio = pcm("scratch/hadev/cmd.wav")
    rows = []
    for i in range(5):
        r = await one(ws, pid, audio, silence_seconds=0.1, turn_detection=True,
                      turn_threshold=0.9, turn_max_seconds=2.0)
        if r and i: rows.append(r)
        await asyncio.sleep(2)
    def med(k):
        vals = [r[k] for r in rows if k in r]
        return statistics.median(vals) if vals else float("nan")
    print("milliseconds after the last sample of speech:\n")
    prev = 0.0
    for stage, label in (("stt-vad-end", "VAD + turn model decided"),
                         ("stt-end", "speech-to-text finished"),
                         ("intent-start", "conversation started"),
                         ("intent-end", "answer ready")):
        v = med(stage)
        print(f"  {label:26} {v:7.0f} ms   (+{v - prev:5.0f})")
        prev = v
asyncio.run(main())
