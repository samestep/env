"""The whole thing, on the host: audio in, audio out.

Streams a clip in real time to the real machine's pipeline and reports when each
stage finished and when the first byte of speech came back. This is the number
that matters -- everything else measured so far is a piece of it.

    dev/py dev/host-e2e.py [repeats] [clip...]

Set HOST_E2E_SETTINGS to a JSON object to override the pipeline's audio
settings for the run, e.g. to turn speculation off and compare.
"""
import asyncio, json, os, statistics, subprocess, sys, time
import aiohttp, websockets

HOST = "192.168.122.1:8123"
TOKEN = open("scratch/ha/token.txt").read().strip()
SR = 16000
CLIPS = ["scratch/hadev/Is_the_kitchen_light_o.wav",
         "scratch/hadev/Turn_off_the_ceiling_l.wav"]


def pcm(path):
    return subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ar", str(SR),
                           "-ac", "1", "-f", "s16le", "-"],
                          capture_output=True, check=True).stdout


async def fetch(session, url, marks, key):
    async with session.get(f"http://{HOST}{url}",
                           headers={"Authorization": f"Bearer {TOKEN}"}) as r:
        async for _ in r.content.iter_chunked(1024):
            if key not in marks:
                marks[key] = time.monotonic()


async def once(ws, ident, pipeline, audio, session, trailing=4, **settings):
    # How finely the audio is fed in. Home Assistant only looks at the stream
    # when a chunk arrives, so this sets the granularity of every decision made
    # from it -- when speech is seen to stop, and so when the snapshot for
    # speculative transcription is taken. A satellite streams continuously; a
    # test client that sends 100 ms at a time makes the pipeline look slower
    # than it is.
    chunk_ms = int(os.environ.get("HOST_E2E_CHUNK_MS", "100"))
    chunk = SR * 2 * chunk_ms // 1000
    stream = audio + bytes(SR * 2 * trailing)
    await ws.send(json.dumps({"id": ident, "type": "assist_pipeline/run",
                              "start_stage": "stt", "end_stage": "tts",
                              "input": {"sample_rate": SR, **settings},
                              "pipeline": pipeline, "timeout": 60}))
    hid = None; pump = None; marks = {}; fetcher = None; text = None

    async def send_audio():
        for i in range(0, len(stream), chunk):
            await ws.send(bytes([hid]) + stream[i:i + chunk])
            if i <= len(audio) < i + chunk:
                marks["speech_ends"] = time.monotonic()
            await asyncio.sleep(chunk_ms / 1000)

    while True:
        m = json.loads(await ws.recv())
        if m.get("id") != ident:
            continue
        if m.get("type") == "result" and not m.get("success"):
            return None, m.get("error")
        if m.get("type") != "event":
            continue
        e = m["event"]
        if e["type"] == "run-start":
            hid = e["data"]["runner_data"]["stt_binary_handler_id"]
            pump = asyncio.create_task(send_audio())
            if (out := e["data"].get("tts_output")):
                fetcher = asyncio.create_task(
                    fetch(session, out["url"], marks, "first_audio"))
        if e["type"] == "stt-end":
            marks["transcribed"] = time.monotonic()
            text = e["data"]["stt_output"]["text"]
        if e["type"] == "intent-end":
            marks["answered"] = time.monotonic()
        if e["type"] in ("run-end", "error"):
            break
    if pump:
        pump.cancel()
    if fetcher:
        await fetcher
    if "speech_ends" not in marks:
        return None, "never saw the end of the audio"
    t0 = marks["speech_ends"]
    return {k: (v - t0) * 1000 for k, v in marks.items() if k != "speech_ends"}, text


async def main():
    repeats = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    clips = sys.argv[2:] or CLIPS
    ws = await websockets.connect(f"ws://{HOST}/api/websocket", max_size=None)
    await ws.recv()
    await ws.send(json.dumps({"type": "auth", "access_token": TOKEN}))
    assert json.loads(await ws.recv())["type"] == "auth_ok"
    await ws.send(json.dumps({"id": 1, "type": "assist_pipeline/pipeline/list"}))
    pref = json.loads(await ws.recv())["result"]["preferred_pipeline"]

    ident = 100
    async with aiohttp.ClientSession() as session:
        for clip in clips:
            audio = pcm(clip)
            print(f"\n{clip.rsplit('/', 1)[-1]}")
            rows = []
            for _ in range(repeats):
                ident += 1
                await ws.send(json.dumps({"id": ident, "type": "call_service",
                                          "domain": "tts", "service": "clear_cache"}))
                while True:
                    m = json.loads(await ws.recv())
                    if m.get("id") == ident and m.get("type") == "result":
                        break
                ident += 1
                marks, text = await once(ws, ident, pref, audio, session,
                                         **json.loads(os.environ.get("HOST_E2E_SETTINGS", "{}")))
                if marks is None:
                    print(f"  ERROR {text}")
                    continue
                rows.append(marks)
                await asyncio.sleep(2)
            if not rows:
                continue
            print(f"  heard {text!r}")
            print("  ms from the last sample of speech:")
            for k in ("transcribed", "answered", "first_audio"):
                vals = [r[k] for r in rows if k in r]
                if vals:
                    print(f"    {statistics.median(vals):7.0f}  {k}")

asyncio.run(main())
