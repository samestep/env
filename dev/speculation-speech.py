"""Nothing is spoken on a guess -- and the real reply still streams.

Home Assistant hands the synthesiser text as the model produces it, so the first
sentence is spoken while the last is still being written. A speculative
conversation produces that same text, and must not reach the synthesiser until
the turn is confirmed. This checks both halves against dev/fake-tts.py, which
answers "what was I asked to say, and when" without needing a GPU.

Run the fake synthesiser first, and add it to Home Assistant as a Wyoming entry
on port 10211:

    dev/py dev/fake-tts.py &
    dev/py dev/speculation-speech.py
"""
import asyncio, json, sys, urllib.request
sys.path.insert(0, "dev")
from halib import (
    SR, TOKEN, connect, ensure_whisper, engines, pcm, pipeline_id, rest, run,
)

JOURNAL = "scratch/spoken.jsonl"
QUESTION = "scratch/hadev/Is_the_kitchen_light_o.wav"
COMMAND = "scratch/hadev/Turn_off_the_ceiling_l.wav"


def spoken():
    with open(JOURNAL) as f:
        return [json.loads(line) for line in f if line.strip()]


def clear():
    open(JOURNAL, "w").close()
    # Home Assistant caches synthesised speech, and these clips draw the same
    # few replies over and over, so without this a run is served from the cache
    # and the server is never asked anything.
    rest("/api/services/tts/clear_cache", {})


async def say_it(url):
    """Pull the audio, the way a satellite does.

    Nothing is synthesised until something asks for it, so a test that only
    watches the pipeline events sees synthesis land whenever -- sometimes inside
    the next test. Fetching makes it deterministic.
    """
    req = urllib.request.Request(f"http://127.0.0.1:8123{url}",
                                 headers={"Authorization": f"Bearer {TOKEN}"})
    return await asyncio.to_thread(
        lambda: urllib.request.urlopen(req, timeout=60).read())


def fetcher(pending):
    """Start pulling the speech as soon as the run says where it is.

    run-start carries the URL when the reply will be streamed into the
    synthesiser, and tts-end when it will not; take whichever comes first.
    """
    def on_event(e):
        out = (e.get("data") or {}).get("tts_output") or {}
        if out.get("url") and not pending:
            pending.append(asyncio.create_task(say_it(out["url"])))
            pending.append(e["type"])
    return on_event


async def main():
    ensure_whisper()
    stt, conv = engines()
    tts = next(s["entity_id"] for s in rest("/api/states")
               if s["entity_id"] == "tts.fake")
    ws = await connect()
    pid = await pipeline_id(ws, "speculation-tts", stt_engine=stt, stt_language="en",
                            conversation_engine=conv, tts_engine=tts,
                            tts_language="en", tts_voice="silence")

    settings = dict(silence_seconds=0.25, turn_detection=True, turn_threshold=0.9,
                    turn_max_seconds=2.0, speculative_intent=True)

    print("1. a plain reply is spoken")
    clear()
    pending = []
    ms, text, reply, err = await run(ws, pid, pcm(QUESTION), end_stage="tts",
                                     on_event=fetcher(pending), **settings)
    if pending:
        await pending[0]
        print(f"   url from {pending[1]}")
    said = [e["text"] for e in spoken() if e["event"] == "speak"]
    print(f"   heard {text!r}\n   said  {said}")
    if err:
        print(f"   error {err}")
    ok_plain = bool(said)
    print("   PASS" if ok_plain else "   FAIL: nothing was spoken")

    print("\n2. an abandoned guess is not spoken")
    clear()
    audio = pcm(COMMAND) + bytes(SR * 2 * 1) + pcm(QUESTION)
    pending = []
    ms, text, reply, err = await run(
        ws, pid, audio, end_stage="tts", on_event=fetcher(pending),
        **{**settings, "turn_threshold": 1.0, "turn_max_seconds": 3.0})
    if pending:
        await pending[0]
        print(f"   url from {pending[1]}")
    events = spoken()
    said = [e["text"] for e in events if e["event"] == "speak"]
    starts = [e for e in events if e["event"] == "start"]
    print(f"   heard {text!r}\n   said  {said}")
    if err:
        print(f"   error {err}")
    # One utterance, spoken once: a leaked guess would have opened a second
    # stream, or spoken the fragment's reply as well as the real one.
    ok_guess = len(starts) <= 1 and len(said) > 0
    print("   PASS" if ok_guess else f"   FAIL: {len(starts)} synthesis streams")

    print("\n" + ("PASS" if ok_plain and ok_guess else "FAIL"))

asyncio.run(main())
