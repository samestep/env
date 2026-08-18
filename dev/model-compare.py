"""Compare conversation models end to end.

qwen35moe was rejected long ago for a CUDA illegal memory access during
constrained decoding of tool calls with array or enum parameters -- which is
what Home Assistant sends. That was ollama 0.32.3; we run 0.32.13.
"""
import asyncio, statistics, sys
sys.path.insert(0, "dev")
from halib import call, connect, engines, ensure_whisper, pcm, pipeline_id, rest, run

MODELS = ["qwen3.8:27b-mtp-q8_0", "qwen3.6:35b-a3b-q4_K_M", "ornith:35b-q4_K_M"]


async def subentry(ws):
    """Subentry ids come from the websocket API; REST only reports the count."""
    entry = next(e for e in rest("/api/config/config_entries/entry")
                 if e["domain"] == "ollama")
    res = await call(ws, type="config_entries/subentries/list",
                     entry_id=entry["entry_id"])
    subs = res["result"]
    return entry["entry_id"], (subs[0]["subentry_id"] if subs else None)


def set_model(entry_id, sub_id, model):
    flow = rest("/api/config/config_entries/subentries/flow",
                {"handler": [entry_id, "conversation"], "subentry_id": sub_id,
                 "show_advanced_options": True})
    cur = {f["name"]: f.get("description", {}).get("suggested_value")
           for f in flow["data_schema"] if "name" in f}
    body = {k: v for k, v in cur.items() if v is not None}
    body["model"] = model
    for k in ("num_ctx", "max_history", "keep_alive"):
        if k in body:
            body[k] = int(body[k])
    res = rest(f"/api/config/config_entries/subentries/flow/{flow['flow_id']}", body)
    return res.get("reason") or res.get("errors")


async def main():
    ensure_whisper()
    ws = await connect()
    entry_id, sub_id = await subentry(ws)
    if sub_id is None:
        print("no ollama conversation subentry; run dev/ha-setup.py first")
        return
    stt, conv = engines()
    pid = await pipeline_id(ws, "e2e", stt_engine=stt, stt_language="en",
                            conversation_engine=conv)
    audio = pcm("scratch/hadev/cmd.wav")
    print(f"{'model':28}{'end of speech -> answer':>26}   reply")
    for model in MODELS:
        problem = set_model(entry_id, sub_id, model)
        if problem != "reconfigure_successful":
            print(f"  {model:26} could not select: {problem}")
            continue
        await asyncio.sleep(2)
        runs, reply, failed = [], "", None
        for i in range(4):
            ms, _text, rep, err = await run(ws, pid, audio, silence_seconds=0.1,
                                            turn_detection=True, turn_threshold=0.9,
                                            turn_max_seconds=2.0)
            if err:
                failed = err
                break
            if i:                       # first call loads the model
                runs.append(ms)
                reply = rep
            await asyncio.sleep(2)
        if failed:
            print(f"  {model:26} ERROR {failed}")
        elif runs:
            print(f"  {model:26} {statistics.median(runs):21.0f} ms   {reply[:32]!r}")
    set_model(entry_id, sub_id, MODELS[0])
    print(f"\nrestored {MODELS[0]}")

asyncio.run(main())
