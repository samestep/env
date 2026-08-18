"""A speculation that turns out wrong must not have changed anything.

Plays a complete command, a pause, then more speech -- the shape of someone who
was not finished. The pipeline starts the conversation on the first fragment,
the model calls a tool that would act, and the call is held. Speech resumes, so
the guess is thrown away with the call still held.

Counting states is not enough: the full utterance contains that command too, so
the light ends up off either way. What distinguishes them is how many times the
service was called -- once if the held call was dropped, twice if it leaked.

turn_threshold is 1.0 so the pause is held however final the fragment sounds:
this is a test of the discard path, not of the turn model.

    dev/speculation-safety.py
"""
import asyncio, json, sys
sys.path.insert(0, "dev")
from halib import SR, connect, ensure_whisper, engines, pcm, pipeline_id, rest, run

ENTITY = "light.ceiling_lights"
COMMAND = "scratch/hadev/Turn_off_the_ceiling_l.wav"
MORE = "scratch/hadev/Is_the_kitchen_light_o.wav"


async def watch(calls):
    """Record every service call Home Assistant makes, on its own connection."""
    ws = await connect()
    await ws.send(json.dumps({"id": 1, "type": "subscribe_events",
                              "event_type": "call_service"}))
    while True:
        m = json.loads(await ws.recv())
        if m.get("type") == "event":
            d = m["event"]["data"]
            calls.append(f"{d['domain']}.{d['service']}")


async def main():
    ensure_whisper()
    stt, conv = engines()
    ws = await connect()
    pid = await pipeline_id(ws, "speculation", stt_engine=stt, stt_language="en",
                            conversation_engine=conv)

    rest("/api/services/light/turn_on", {"entity_id": ENTITY})
    await asyncio.sleep(1)

    calls: list[str] = []
    watcher = asyncio.create_task(watch(calls))
    await asyncio.sleep(1)
    calls.clear()

    # A command, a pause long enough to speculate in, then more speech.
    audio = pcm(COMMAND) + bytes(SR * 2 * 1) + pcm(MORE)
    ms, text, reply, err = await run(
        ws, pid, audio, silence_seconds=0.25, turn_detection=True,
        turn_threshold=1.0, turn_max_seconds=3.0, speculative_intent=True)
    await asyncio.sleep(2)
    watcher.cancel()

    print(f"heard: {text!r}")
    print(f"reply: {reply!r}")
    off = [c for c in calls if c == "light.turn_off"]
    print(f"service calls: {calls}")
    print(f"\nlight.turn_off called {len(off)} time(s)")
    print("PASS: the held call was dropped with the guess" if len(off) == 1
          else "FAIL: the abandoned speculation acted as well")

asyncio.run(main())
