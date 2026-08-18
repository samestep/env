#!/usr/bin/env python3
"""Onboard a fresh development Home Assistant and save a long-lived token.

Run once after dev/run-ha.sh on an empty config dir. Idempotent enough: if
onboarding is already done it just reports that.
"""
import asyncio, json, os, sys, urllib.error, urllib.request

HA = os.environ.get("HA_DEV_URL", "http://127.0.0.1:8123")
HERE = os.path.dirname(os.path.abspath(__file__))
TOKEN_FILE = os.path.join(HERE, "..", "scratch", "hadev", "token.txt")


def post(path, body, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(HA + path, json.dumps(body).encode(), headers)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


steps = json.load(urllib.request.urlopen(HA + "/api/onboarding", timeout=30))
if all(s["done"] for s in steps):
    sys.exit("already onboarded; delete the config dir to start over")

auth = post("/api/onboarding/users",
            {"client_id": HA + "/", "name": "Agent", "username": "agent",
             "password": "devdevdev", "language": "en"})
import urllib.parse
req = urllib.request.Request(
    HA + "/auth/token",
    urllib.parse.urlencode({"grant_type": "authorization_code",
                            "code": auth["auth_code"],
                            "client_id": HA + "/"}).encode())
short = json.load(urllib.request.urlopen(req, timeout=30))["access_token"]

for step in ("core_config", "analytics"):
    try:
        post("/api/onboarding/" + step, {"client_id": HA + "/"}, short)
    except urllib.error.HTTPError as e:
        print(f"  {step}: {e.code} (continuing)")


async def long_lived():
    import websockets
    async with websockets.connect(HA.replace("http", "ws") + "/api/websocket") as ws:
        await ws.recv()
        await ws.send(json.dumps({"type": "auth", "access_token": short}))
        assert json.loads(await ws.recv())["type"] == "auth_ok"
        await ws.send(json.dumps({"id": 1, "type": "auth/long_lived_access_token",
                                  "client_name": "agent", "lifespan": 3650}))
        while True:
            m = json.loads(await ws.recv())
            if m.get("id") == 1:
                if not m.get("success"):
                    raise SystemExit(m)
                return m["result"]


tok = asyncio.run(long_lived())
os.makedirs(os.path.dirname(TOKEN_FILE), exist_ok=True)
with open(TOKEN_FILE, "w") as f:
    f.write(tok)
print(f"onboarded; long-lived token written to {os.path.relpath(TOKEN_FILE, os.getcwd())}")
