#!/usr/bin/env python3
"""Ask the development assistant something and time the intent stage.

    python3 dev/ha-ask.py "is the bed light on?"
"""
import asyncio, json, os, sys, time
import websockets

HA = os.environ.get("HA_DEV_URL", "http://127.0.0.1:8123")
HERE = os.path.dirname(os.path.abspath(__file__))
TOKEN = open(os.path.join(HERE, "..", "scratch", "hadev", "token.txt")).read().strip()
QUESTIONS = sys.argv[1:] or ["Is the bed light on?", "Turn on the kitchen lights.",
                             "What time is it?"]


async def main():
    ws = await websockets.connect(HA.replace("http", "ws") + "/api/websocket",
                                  max_size=None)
    await ws.recv()
    await ws.send(json.dumps({"type": "auth", "access_token": TOKEN}))
    assert json.loads(await ws.recv())["type"] == "auth_ok"
    await ws.send(json.dumps({"id": 1, "type": "assist_pipeline/pipeline/list"}))
    while True:
        m = json.loads(await ws.recv())
        if m.get("id") == 1:
            pipe = next(p["id"] for p in m["result"]["pipelines"] if p["name"] == "Dev")
            break
    i = 100
    for q in QUESTIONS:
        i += 1
        await ws.send(json.dumps({"id": i, "type": "assist_pipeline/run",
            "start_stage": "intent", "end_stage": "intent", "input": {"text": q},
            "pipeline": pipe, "timeout": 120}))
        marks, reply = {}, ""
        while True:
            m = json.loads(await ws.recv())
            if m.get("id") != i:
                continue
            if m.get("type") == "result" and not m.get("success"):
                print("ERR", m.get("error")); return
            if m.get("type") != "event":
                continue
            e = m["event"]; marks[e["type"]] = time.monotonic()
            if e["type"] == "intent-end":
                reply = e["data"]["intent_output"]["response"]["speech"]["plain"]["speech"]
            if e["type"] in ("run-end", "error"):
                break
        dur = (marks.get("intent-end", 0) - marks.get("intent-start", 0)) * 1000
        print(f"{dur:7.0f} ms  {q}\n          -> {reply}")
        await asyncio.sleep(1)

asyncio.run(main())
