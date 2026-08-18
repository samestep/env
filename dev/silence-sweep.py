"""How low can silence_seconds go once a turn model is catching continuations?

Two things matter and they pull apart: a finished utterance should end fast, and
a natural mid-sentence pause should still be held open. Measures both.
"""
import asyncio, json, sys
sys.argv = sys.argv[:1]
exec(open("dev/turn-test.py").read().split("async def main")[0])

COMPLETE = "scratch/ha/ldc.wav"     # one finished sentence
PAUSED = "scratch/ha/jfk.wav"       # pauses mid-sentence, dramatically

async def main():
    ensure_whisper()
    ws = await websockets.connect(URL, max_size=None); await ws.recv()
    await ws.send(json.dumps({"type": "auth", "access_token": TOKEN}))
    assert json.loads(await ws.recv())["type"] == "auth_ok"
    pls = (await call(ws, 1, type="assist_pipeline/pipeline/list"))["result"]["pipelines"]
    pid = next(p["id"] for p in pls if p.get("name") == "turn-test")
    done, paused = pcm(COMPLETE), pcm(PAUSED)[: 16000 * 2 * 6]
    ident = 200
    print(f"{'silence':>9} {'turn':>6}   {'finished utterance':>28}   {'mid-sentence pause':>30}")
    for ss in (0.10, 0.15, 0.25, 0.40, 0.70):
        for td in (False, True):
            ident += 1
            t1, e1, _ = await run(ws, ident, pid, done, silence_seconds=ss,
                                  turn_detection=td, turn_threshold=0.9,
                                  turn_max_seconds=2.0)
            ident += 1
            t2, e2, _ = await run(ws, ident, pid, paused, silence_seconds=ss,
                                  turn_detection=td, turn_threshold=0.9,
                                  turn_max_seconds=2.0)
            held = "held" if (t2 and "ASK" in (t2 or "").upper()) else "cut short"
            print(f"{ss:>9} {str(td):>6}   {(e1 or 0):>7.1f}s {str(t1)[:19]:>20}   "
                  f"{(e2 or 0):>7.1f}s {held:>10} {str(t2)[:12]}")
            await asyncio.sleep(1)

asyncio.run(main())
