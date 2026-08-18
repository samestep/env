"""Does starting the conversation on a guess make the answer arrive sooner --
and is it the same answer?

Runs each clip with speculative_intent off and on, alternating, and reports the
time from the last sample of speech to intent-end. The replies are compared as
well: speculation is only worth having if it changes nothing but the timing.

    dev/speculation-compare.py [repeats] [clip...]
"""
import asyncio, statistics, sys
sys.path.insert(0, "dev")
from halib import connect, ensure_whisper, engines, pcm, pipeline_id, run

CLIPS = ["scratch/hadev/Is_the_kitchen_light_o.wav",
         "scratch/hadev/Set_the_bed_light_to_f.wav",
         "scratch/hadev/Turn_off_the_ceiling_l.wav"]

BASE = dict(silence_seconds=0.25, turn_detection=True, turn_threshold=0.9,
            turn_max_seconds=2.0)


async def main():
    repeats = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    clips = sys.argv[2:] or CLIPS
    ensure_whisper()
    stt, conv = engines()
    ws = await connect()
    pid = await pipeline_id(ws, "speculation", stt_engine=stt, stt_language="en",
                            conversation_engine=conv)
    print(f"conversation agent: {conv}\n")

    for clip in clips:
        audio = pcm(clip)
        print(clip.rsplit("/", 1)[-1])
        results = {}
        for _ in range(repeats):
            for on in (False, True):
                ms, text, reply, err = await run(
                    ws, pid, audio, speculative_intent=on, **BASE)
                if err:
                    print(f"  ERROR {err}")
                    continue
                results.setdefault(on, []).append((ms, text, reply))
                await asyncio.sleep(2)
        for on in (False, True):
            runs = results.get(on)
            if not runs:
                continue
            label = "speculation on " if on else "speculation off"
            median = statistics.median(r[0] for r in runs)
            replies = {r[2] for r in runs}
            print(f"  {label}  {median:6.0f} ms   {len(replies)} distinct reply")
            for r in sorted(replies):
                print(f"      {r[:70]!r}")
        if results.get(False) and results.get(True):
            off = statistics.median(r[0] for r in results[False])
            onn = statistics.median(r[0] for r in results[True])
            print(f"  -> {off - onn:.0f} ms saved\n")

asyncio.run(main())
