"""Force repeated tool calls on each model, watching for the CUDA fault.

qwen35moe was rejected for a CUDA illegal memory access during constrained
decoding of tool calls with array or enum parameters. A question answered from
the prompt never exercises that path; a control command does.
"""
import asyncio, statistics, sys
sys.path.insert(0, "dev")
from halib import connect, engines, ensure_whisper, pcm, pipeline_id, rest, run
from importlib import import_module
mc = import_module("model-compare".replace("-", "_")) if False else None

MODELS = ["qwen3.8:27b-mtp-q8_0", "qwen3.6:35b-a3b-q4_K_M", "ornith:35b-q4_K_M"]
REPS = 6


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
    return rest(f"/api/config/config_entries/subentries/flow/{flow['flow_id']}",
                body).get("reason")


async def main():
    ensure_whisper()
    ws = await connect()
    from halib import call
    entry = next(e for e in rest("/api/config/config_entries/entry")
                 if e["domain"] == "ollama")
    subs = (await call(ws, type="config_entries/subentries/list",
                       entry_id=entry["entry_id"]))["result"]
    entry_id, sub_id = entry["entry_id"], subs[0]["subentry_id"]
    stt, conv = engines()
    pid = await pipeline_id(ws, "e2e", stt_engine=stt, stt_language="en",
                            conversation_engine=conv)
    audio = pcm("scratch/hadev/cmd2.wav")
    print(f'"Turn on the kitchen lights." x{REPS}, which needs a tool call\n')
    print(f"{'model':28}{'median':>9}  {'ok':>5}  errors / replies")
    for model in MODELS:
        if set_model(entry_id, sub_id, model) != "reconfigure_successful":
            print(f"  {model:26} could not select"); continue
        await asyncio.sleep(2)
        times, errs, replies = [], [], set()
        for i in range(REPS + 1):
            ms, _t, rep, err = await run(ws, pid, audio, silence_seconds=0.1,
                                         turn_detection=True, turn_threshold=0.9,
                                         turn_max_seconds=2.0)
            if err:
                errs.append(str(err)[:60])
            elif i:
                times.append(ms); replies.add(rep[:28])
            await asyncio.sleep(1.5)
        med = f"{statistics.median(times):.0f} ms" if times else "--"
        print(f"  {model:26}{med:>9}  {len(times):5d}  "
              f"{('; '.join(errs[:2]) if errs else sorted(replies)[:1])}")
    set_model(entry_id, sub_id, MODELS[0])
    print(f"\nrestored {MODELS[0]}")

asyncio.run(main())
