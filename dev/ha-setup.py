#!/usr/bin/env python3
"""Configure a fresh development Home Assistant to mirror the real one.

Reproducible so the dev instance never drifts into a state nobody can rebuild.
Idempotent: re-running reuses whatever already exists.

    nix run .#hass-dev -- -c ~/ha-dev        # start it
    python3 dev/ha-setup.py                  # configure it

Talks to 127.0.0.1:8123 (the dev instance) and points its conversation agent at
the ollama on the NixOS host, which is the one thing here that needs a GPU.
"""
import asyncio, json, os, sys, urllib.error, urllib.request

HA = os.environ.get("HA_DEV_URL", "http://127.0.0.1:8123")
OLLAMA = os.environ.get("HA_DEV_OLLAMA", "http://192.168.122.1:11434")
MODEL = os.environ.get("HA_DEV_MODEL", "qwen3.8:27b-mtp-q8_0")
TOKEN = open(os.path.join(os.path.dirname(__file__) or ".",
                          "../scratch/hadev/token.txt")).read().strip()

# Mirrors the real machine's prompt. Everything after <|fim_pad|> is re-read on
# every request; everything before it is cached. See packages/prefix-cache-findings.md.
PROMPT = """You are a voice assistant for Home Assistant.
Answer in plain text. Keep it simple and to the point: one or two short sentences unless asked for detail.

Your training data is out of date and your memory of current facts is wrong.
The current time and the state of the devices listed at the very end of this prompt are live; trust them over anything you remember, and answer from them directly without calling a tool.
Call GetLiveContext only for the state of something not listed there.
Never say you lack access to current information. Only say you do not know if a tool returned nothing useful.
<|fim_pad|>
Live state, correct as of now:
Current time: {{ now().strftime('%A, %B %-d, %Y at %-I:%M %p %Z') }}
Bed Light: {{ states('light.bed_light') }}
Ceiling Lights: {{ states('light.ceiling_lights') }}
Kitchen Lights: {{ states('light.kitchen_lights') }}"""

EXPOSE = ["light.bed_light", "light.ceiling_lights", "light.kitchen_lights",
          "weather.forecast_home"]


def rest(path, body=None, method=None):
    req = urllib.request.Request(
        HA + path,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Content-Type": "application/json",
                 "Authorization": "Bearer " + TOKEN},
        method=method)
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def ollama_entry():
    """Create the ollama config entry, or return the existing one."""
    for e in rest("/api/config/config_entries/entry"):
        if e["domain"] == "ollama":
            print(f"  ollama entry exists: {e['entry_id']}")
            return e["entry_id"]
    flow = rest("/api/config/config_entries/flow",
                {"handler": "ollama", "show_advanced_options": True})
    res = rest(f"/api/config/config_entries/flow/{flow['flow_id']}", {"url": OLLAMA})
    if res.get("type") == "create_entry":
        entry = res["result"]["entry_id"]
        print(f"  created ollama entry {entry} -> {OLLAMA}")
        return entry
    raise SystemExit(f"unexpected flow result: {json.dumps(res)[:400]}")


def conversation_subentry(entry_id, existing_id=None):
    """Create the conversation agent, or reconfigure the one that exists."""
    body = {"handler": [entry_id, "conversation"], "show_advanced_options": True}
    if existing_id:
        body["subentry_id"] = existing_id          # reconfigure rather than add
    flow = rest("/api/config/config_entries/subentries/flow", body)
    data = {"model": MODEL, "prompt": PROMPT, "llm_hass_api": ["assist"],
            "num_ctx": 8192, "max_history": 20, "keep_alive": -1, "think": False}
    res = rest(f"/api/config/config_entries/subentries/flow/{flow['flow_id']}", data)
    print(f"  conversation agent: {res.get('type')} {res.get('reason', '')} model={MODEL}")


async def ws_setup():
    import websockets
    async with websockets.connect(HA.replace("http", "ws") + "/api/websocket",
                                  max_size=None) as ws:
        await ws.recv()
        await ws.send(json.dumps({"type": "auth", "access_token": TOKEN}))
        assert json.loads(await ws.recv())["type"] == "auth_ok"
        n = [0]

        async def call(**kw):
            n[0] += 1
            await ws.send(json.dumps({"id": n[0], **kw}))
            while True:
                m = json.loads(await ws.recv())
                if m.get("id") == n[0] and m.get("type") == "result":
                    return m

        r = await call(type="homeassistant/expose_entity",
                       assistants=["conversation"], entity_ids=EXPOSE, should_expose=True)
        print(f"  exposed {len(EXPOSE)} entities: {r.get('success')}")

        pipelines = await call(type="assist_pipeline/pipeline/list")
        if not pipelines.get("success"):
            print(f"  pipeline/list failed: {pipelines.get('error')}")
            return
        agents = await call(type="conversation/agent/list")
        agent = next((a["id"] for a in agents["result"]["agents"]
                      if a["id"] != "conversation.home_assistant"), None)
        print(f"  conversation agents: {[a['id'] for a in agents['result']['agents']]}")
        if agent is None:
            print("  !! no LLM agent yet; re-run after the entry finishes setting up")
            return
        existing = next((p for p in pipelines["result"]["pipelines"]
                         if p["name"] == "Dev"), None)
        spec = {"name": "Dev", "language": "en", "conversation_engine": agent,
                "conversation_language": "en", "stt_engine": None, "stt_language": None,
                "tts_engine": None, "tts_language": None, "tts_voice": None,
                "wake_word_entity": None, "wake_word_id": None,
                "prefer_local_intents": True}
        if existing:
            r = await call(type="assist_pipeline/pipeline/update",
                           pipeline_id=existing["id"], **spec)
            print(f"  updated pipeline {existing['id']}: {r.get('success')}")
        else:
            r = await call(type="assist_pipeline/pipeline/create", **spec)
            print(f"  created pipeline: {r['result']['id'] if r.get('success') else r}")


async def existing_subentry(entry_id):
    import websockets
    async with websockets.connect(HA.replace("http", "ws") + "/api/websocket",
                                  max_size=None) as ws:
        await ws.recv()
        await ws.send(json.dumps({"type": "auth", "access_token": TOKEN}))
        assert json.loads(await ws.recv())["type"] == "auth_ok"
        await ws.send(json.dumps({"id": 1, "type": "config_entries/subentries/list",
                                  "entry_id": entry_id}))
        while True:
            m = json.loads(await ws.recv())
            if m.get("id") == 1 and m.get("type") == "result":
                subs = [s for s in m.get("result", [])
                        if s["subentry_type"] == "conversation"]
                return subs[0]["subentry_id"] if subs else None


print(f"configuring dev Home Assistant at {HA}")
entry = ollama_entry()
conversation_subentry(entry, asyncio.run(existing_subentry(entry)))
asyncio.run(ws_setup())
print("done")
