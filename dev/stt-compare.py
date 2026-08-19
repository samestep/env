"""Which transcriber, and what it costs.

The host runs wyoming-faster-whisper with `model = "auto"`. That looks like it
picks the best available, but the sherpa-onnx bindings live in an optional
extra that is not installed, so the Parakeet branch is unreachable and it falls
back to whisper-base-int8. This transcribes the same clips through both and
reports the text and the time.

Start each server first; they are separate processes on separate ports.

    dev/py dev/stt-compare.py <port>:<label> [<port>:<label>...]
"""
import asyncio, statistics, subprocess, sys, time
from wyoming.asr import Transcribe, Transcript
from wyoming.audio import AudioChunk, AudioStart, AudioStop
from wyoming.client import AsyncTcpClient
from wyoming.info import Describe, Info

SR = 16000
CLIPS = ["scratch/hadev/Is_the_kitchen_light_o.wav",
         "scratch/hadev/Set_the_bed_light_to_f.wav",
         "scratch/hadev/Turn_off_the_ceiling_l.wav",
         "scratch/hadev/What_is_the_weather_fo.wav"]


def pcm(path):
    return subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ar", str(SR),
                           "-ac", "1", "-f", "s16le", "-"],
                          capture_output=True, check=True).stdout


async def describe(port):
    async with AsyncTcpClient("127.0.0.1", port) as c:
        await c.write_event(Describe().event())
        while True:
            e = await c.read_event()
            if e is None:
                return "?"
            if Info.is_type(e.type):
                info = Info.from_event(e)
                return info.asr[0].models[0].name if info.asr else "?"


async def transcribe(port, audio):
    t0 = time.monotonic()
    async with AsyncTcpClient("127.0.0.1", port) as c:
        await c.write_event(Transcribe(language="en").event())
        await c.write_event(AudioStart(rate=SR, width=2, channels=1).event())
        for i in range(0, len(audio), 3200):
            await c.write_event(AudioChunk(rate=SR, width=2, channels=1,
                                           audio=audio[i:i + 3200]).event())
        await c.write_event(AudioStop().event())
        while True:
            e = await c.read_event()
            if e is None:
                return None, (time.monotonic() - t0) * 1000
            if Transcript.is_type(e.type):
                return Transcript.from_event(e).text, (time.monotonic() - t0) * 1000


async def main():
    targets = [(int(a.split(":")[0]), a.split(":", 1)[1]) for a in sys.argv[1:]]
    if not targets:
        print(__doc__)
        return
    clips = [(c.rsplit("/", 1)[-1][:22], pcm(c)) for c in CLIPS]

    for port, label in targets:
        model = await describe(port)
        print(f"\n{label}  (port {port}, model {model})")
        times = []
        for name, audio in clips:
            await transcribe(port, audio)          # warm, so the load is not timed
            runs = [await transcribe(port, audio) for _ in range(3)]
            ms = statistics.median(r[1] for r in runs)
            times.append(ms)
            print(f"  {ms:6.0f} ms  {runs[-1][0]!r}")
        print(f"  median across clips: {statistics.median(times):.0f} ms")

asyncio.run(main())
