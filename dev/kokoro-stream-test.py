"""Drive the patched Kokoro server's protocol handling with a stub synthesiser.

Building the real thing needs onnxruntime with CUDA, which is irrelevant to what
changed: this exercises the event handling, the sentence splitting, and the order
of the audio events Home Assistant expects.

The exchange is exactly the one Home Assistant performs, including the plain
Synthesize carrying the whole message that it sends after the chunks "for
backwards compatibility". A server that streams has already said all of it, and
must ignore it -- the first version of this test left it out, and the reply was
synthesised twice for a day before anything noticed.

    dev/py dev/kokoro-stream-test.py <path to main.py>
"""
import asyncio, importlib.util, sys, types

import numpy as np

# main.py imports kokoro_onnx at module scope; stand in for it.
import logging

fake = types.ModuleType("kokoro_onnx")
fake.__path__ = []                      # make it a package, it has submodules
fake.config = types.SimpleNamespace(SAMPLE_RATE=24000, MAX_PHONEME_LENGTH=510)
fake.Kokoro = object
fake.EspeakConfig = object
fake_log = types.ModuleType("kokoro_onnx.log")
fake_log.log = logging.getLogger("stub")
fake_config = types.ModuleType("kokoro_onnx.config")
fake_config.SAMPLE_RATE = 24000
fake_config.MAX_PHONEME_LENGTH = 510
sys.modules["kokoro_onnx"] = fake
sys.modules["kokoro_onnx.log"] = fake_log
sys.modules["kokoro_onnx.config"] = fake_config

spec = importlib.util.spec_from_file_location("kmain", sys.argv[1])
kmain = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kmain)

from wyoming.audio import AudioChunk, AudioStart, AudioStop
from wyoming.tts import (
    Synthesize, SynthesizeChunk, SynthesizeStart, SynthesizeStop, SynthesizeStopped,
)


class StubKokoro:
    def __init__(self):
        self.spoken = []

    def create_stream(self, text, voice, speed, lang):
        self.spoken.append(text)

        async def gen():
            yield np.zeros(2400, dtype=np.float32), 24000

        return gen()


class Recorder(kmain.KokoroEventHandler):
    def __init__(self, kokoro):
        self.kokoro = kokoro
        self.default_voice = "af_heart"
        self.default_speed = 1.0
        self.wyoming_info_event = None
        self._semaphore = asyncio.Semaphore(1)
        self._cache = None
        self._stream_voice = "af_heart"
        self._stream_buffer = ""
        self._stream_started = False
        self._streaming = False
        self._stream_t0 = 0.0
        self.events = []

    async def write_event(self, event):
        self.events.append(event)


async def main():
    stub = StubKokoro()
    h = Recorder(stub)
    await h.handle_event(SynthesizeStart(voice=None).event())
    # A reply arriving the way a language model produces it.
    for piece in ["The bed ", "light is off. ", "The kitchen ", "lights are on",
                  ". Anything else?"]:
        await h.handle_event(SynthesizeChunk(text=piece).event())
        n = sum(AudioChunk.is_type(e.type) for e in h.events)
        print(f"  after {piece!r:22} synthesised={stub.spoken!r:60} audio chunks={n}")
    # What Home Assistant sends next: the whole message, again.
    whole = "The bed light is off. The kitchen lights are on. Anything else?"
    await h.handle_event(Synthesize(text=whole).event())
    print(f"  after the trailing Synthesize   synthesised={stub.spoken!r}")
    await h.handle_event(SynthesizeStop().event())

    kinds = [e.type for e in h.events]
    print(f"\n  sentences synthesised: {stub.spoken}")
    print(f"  event order: {kinds[0]} ... {kinds[-2]} {kinds[-1]}")
    ok = (
        AudioStart.is_type(kinds[0])
        and AudioStop.is_type(kinds[-2])
        and SynthesizeStopped.is_type(kinds[-1])
        and stub.spoken == ["The bed light is off.", "The kitchen lights are on.",
                            "Anything else?"]
    )
    print(f"\n  {'PASS' if ok else 'FAIL'}")

asyncio.run(main())
