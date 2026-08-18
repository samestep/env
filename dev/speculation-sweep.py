"""What speculating on the conversation is worth, against how long the wait is.

The wait for silence is the one thing speculation cannot remove: the answer
still must not arrive before the speaker is known to have finished. What it
removes is the work that used to happen *after* the wait. So the interesting
number is not the saving at one setting but how flat the curve gets: if the
model finishes inside the wait, a longer and safer wait costs nothing.

    dev/speculation-sweep.py [repeats]
"""
import asyncio, statistics, sys
sys.path.insert(0, "dev")
from halib import connect, ensure_whisper, engines, pcm, pipeline_id, run

CLIPS = {"question": "scratch/hadev/Is_the_kitchen_light_o.wav",
         "command": "scratch/hadev/Turn_off_the_ceiling_l.wav"}
SILENCES = (0.1, 0.25, 0.7)


async def main():
    repeats = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    ensure_whisper()
    stt, conv = engines()
    ws = await connect()
    pid = await pipeline_id(ws, "speculation", stt_engine=stt, stt_language="en",
                            conversation_engine=conv)
    print(f"conversation agent: {conv}")
    print(f"{repeats} runs per cell, median ms from last sample of speech to answer\n")

    for name, clip in CLIPS.items():
        audio = pcm(clip)
        print(f"  {name:9} {'silence':>9} {'off':>8} {'on':>8} {'saved':>8}")
        for silence in SILENCES:
            got = {}
            for _ in range(repeats):
                for on in (False, True):
                    ms, text, reply, err = await run(
                        ws, pid, audio, silence_seconds=silence,
                        turn_detection=True, turn_threshold=0.9,
                        turn_max_seconds=2.0, speculative_intent=on)
                    if err:
                        print(f"    ERROR {err}")
                        continue
                    got.setdefault(on, []).append(ms)
                    await asyncio.sleep(1.5)
            if not (got.get(False) and got.get(True)):
                continue
            off = statistics.median(got[False])
            onn = statistics.median(got[True])
            print(f"  {'':9} {silence:9.2f} {off:8.0f} {onn:8.0f} {off - onn:8.0f}")
        print()

asyncio.run(main())
