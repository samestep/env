"""How much of the latency is avoidable by never reaching the model at all.

With prefer_local_intents on, Home Assistant matches commands against its own
sentence templates first and only falls back to the conversation agent when
nothing matches. A match costs a few milliseconds; a miss costs the whole model
round trip. Matching is strict -- exact wording, exact entity name -- so whether
a phrase is fast depends entirely on what the entity happens to be called.

Aliases are the lever. This measures a phrase before and after adding one.

    dev/py dev/local-intent-test.py
"""
import asyncio, statistics, sys, time
sys.path.insert(0, "dev")
from halib import call, connect, engines, pipeline_id, rest

ENTITY = "light.ceiling_lights"
EXACT = "Turn off the Ceiling Lights."
LOOSE = "Turn off the ceiling light."
ALIAS = "ceiling light"


async def timed(ws, pid, text, repeats=3):
    out = []
    for _ in range(repeats):
        ident = None
        ms, kind, speech = await one(ws, pid, text)
        out.append((ms, kind, speech))
        await asyncio.sleep(1)
    return statistics.median(m for m, _, _ in out), out[-1][1], out[-1][2]


async def one(ws, pid, text):
    import json
    from halib import _ident
    ident = _ident()
    await ws.send(json.dumps({"id": ident, "type": "assist_pipeline/run",
                              "start_stage": "intent", "end_stage": "intent",
                              "input": {"text": text}, "pipeline": pid, "timeout": 60}))
    t0 = time.monotonic()
    while True:
        m = json.loads(await ws.recv())
        if m.get("id") != ident or m.get("type") != "event":
            continue
        e = m["event"]
        if e["type"] == "intent-end":
            r = e["data"]["intent_output"]["response"]
            return ((time.monotonic() - t0) * 1000, r["response_type"],
                    r["speech"]["plain"]["speech"])
        if e["type"] == "error":
            return (time.monotonic() - t0) * 1000, "error", str(e["data"])


async def aliases(ws, value):
    res = await call(ws, type="config/entity_registry/update",
                     entity_id=ENTITY, aliases=value)
    return res["result"]["entity_entry"]["aliases"]


async def main():
    stt, conv = engines()
    ws = await connect()
    pid = await pipeline_id(ws, "local-intents", stt_engine=stt, stt_language="en",
                            conversation_engine=conv, prefer_local_intents=True)

    print(f"{'phrase':32} {'alias':8} {'ms':>7}  {'result':14} reply")
    await aliases(ws, [])
    for label, text in (("exact", EXACT), ("loose", LOOSE)):
        ms, kind, speech = await timed(ws, pid, text)
        print(f"  {text:30} {'none':8} {ms:7.0f}  {kind:14} {speech[:34]!r}")

    got = await aliases(ws, [ALIAS])
    print(f"\n  added alias {got}\n")
    for label, text in (("exact", EXACT), ("loose", LOOSE)):
        ms, kind, speech = await timed(ws, pid, text)
        print(f"  {text:30} {ALIAS:8} {ms:7.0f}  {kind:14} {speech[:34]!r}")

    await aliases(ws, [])

asyncio.run(main())
