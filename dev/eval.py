"""Score conversation models on scenarios, against the development instance.

Latency scripts cannot tell you whether a model does the right thing. Each
scenario sets entity state, says something, and checks either the resulting
state or the words of the reply. State is reset before every single run, so a
light left on by one scenario cannot make the next one look correct.

    dev/eval.py [reps] [model ...]
"""
import asyncio, json, statistics, sys, time
sys.path.insert(0, "dev")
from halib import call, connect, engines, rest

SCENARIOS = json.load(open("dev/scenarios.json"))


def set_state(entity, state):
    rest(f"/api/states/{entity}", {"state": state})


def get_state(entity):
    try:
        return rest(f"/api/states/{entity}")["state"]
    except Exception:
        return None


async def set_model(ws, entry_id, sub_id, model):
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


async def say(ws, pipeline, text):
    ident_start = time.monotonic()
    await ws.send(json.dumps({"id": (ident := _next()), "type": "assist_pipeline/run",
                              "start_stage": "intent", "end_stage": "intent",
                              "input": {"text": text}, "pipeline": pipeline,
                              "timeout": 120}))
    reply = ""
    while True:
        m = json.loads(await ws.recv())
        if m.get("id") != ident:
            continue
        if m.get("type") == "result" and not m.get("success"):
            return "", 0.0
        if m.get("type") != "event":
            continue
        e = m["event"]
        if e["type"] == "intent-end":
            reply = e["data"]["intent_output"]["response"]["speech"]["plain"]["speech"]
        if e["type"] in ("run-end", "error"):
            break
    return reply, (time.monotonic() - ident_start) * 1000


_id = 1000
def _next():
    global _id
    _id += 1
    return _id


async def main():
    reps = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    models = sys.argv[2:] or ["qwen3.8:27b-mtp-q8_0"]
    ws = await connect()
    entry = next(e for e in rest("/api/config/config_entries/entry")
                 if e["domain"] == "ollama")
    subs = (await call(ws, type="config_entries/subentries/list",
                       entry_id=entry["entry_id"]))["result"]
    entry_id, sub_id = entry["entry_id"], subs[0]["subentry_id"]
    _stt, conv = engines()
    pls = (await call(ws, type="assist_pipeline/pipeline/list"))["result"]["pipelines"]
    pipe = next((p["id"] for p in pls if p.get("conversation_engine") == conv), None)
    if pipe is None:
        res = await call(ws, type="assist_pipeline/pipeline/create", name="eval",
                         language="en", conversation_engine=conv,
                         conversation_language="en", stt_engine=None, stt_language=None,
                         tts_engine=None, tts_language=None, tts_voice=None,
                         wake_word_entity=None, wake_word_id=None)
        pipe = res["result"]["id"]

    for model in models:
        if await set_model(ws, entry_id, sub_id, model) != "reconfigure_successful":
            print(f"{model}: could not select"); continue
        await asyncio.sleep(2)
        await say(ws, pipe, "hello")           # load the model
        print(f"\n### {model}")
        total = passed = 0
        latencies = []
        for sc in SCENARIOS:
            ok = 0
            for _ in range(reps):
                for entity, state in (sc.get("setup") or {}).items():
                    set_state(entity, state)
                reply, ms = await say(ws, pipe, sc["say"])
                latencies.append(ms)
                good = True
                for entity, want in (sc.get("expect_state") or {}).items():
                    if get_state(entity) != want:
                        good = False
                if sc.get("expect_any"):
                    good = good and any(w.lower() in reply.lower()
                                        for w in sc["expect_any"])
                ok += good
                await asyncio.sleep(0.3)
            total += reps; passed += ok
            flag = "" if ok == reps else f"   <- {ok}/{reps}"
            print(f"  {sc['id']:16} {ok}/{reps}{flag}")
        print(f"  {'TOTAL':16} {passed}/{total}   median {statistics.median(latencies):.0f} ms")

asyncio.run(main())
