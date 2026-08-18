"""A text-to-speech server that says nothing, and writes down what it was asked.

Kokoro needs CUDA, so the real synthesiser cannot run in this VM -- but the
question "did the pipeline ask for this to be spoken, and when" does not need a
synthesiser to answer. This advertises streaming synthesis, accepts both the
one-shot and the streamed form, returns silence, and appends a line per sentence
to its journal.

    dev/py dev/fake-tts.py [--uri tcp://127.0.0.1:10211] [--journal scratch/spoken.jsonl]
"""
import argparse, asyncio, json, time
from wyoming.audio import AudioChunk, AudioStart, AudioStop
from wyoming.event import Event
from wyoming.info import Attribution, Describe, Info, TtsProgram, TtsVoice
from wyoming.server import AsyncEventHandler, AsyncServer
from wyoming.tts import (
    Synthesize, SynthesizeChunk, SynthesizeStart, SynthesizeStop, SynthesizeStopped,
)

RATE, WIDTH, CHANNELS = 22050, 2, 1
ENDINGS = ".!?"


def take_complete_sentences(buffer: str) -> tuple[list[str], str]:
    """Split off what is certainly finished, keeping the rest for later text."""
    cut = max((buffer.rfind(c) for c in ENDINGS), default=-1)
    if cut < 0:
        return [], buffer
    done, rest = buffer[: cut + 1], buffer[cut + 1 :]
    return [s.strip() for s in done.replace("! ", "!|").replace("? ", "?|")
            .replace(". ", ".|").split("|") if s.strip()], rest


class Handler(AsyncEventHandler):
    def __init__(self, info, journal, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.info = info
        self.journal = journal
        self.buffer = ""
        self.started = False
        self.streaming = False

    def note(self, what, text):
        with open(self.journal, "a") as f:
            f.write(json.dumps({"at": time.time(), "event": what, "text": text}) + "\n")

    async def speak(self, text):
        self.note("speak", text)
        if not self.started:
            await self.write_event(
                AudioStart(rate=RATE, width=WIDTH, channels=CHANNELS).event())
            self.started = True
        # A tenth of a second of silence, so there is something to receive.
        await self.write_event(AudioChunk(
            rate=RATE, width=WIDTH, channels=CHANNELS,
            audio=bytes(RATE * WIDTH // 10)).event())

    async def finish(self):
        if not self.started:
            # Even with nothing to say, the client needs a header before the
            # stop or it waits for audio that never comes. The real server does
            # this too; a stand-in that skipped it would hang Home Assistant
            # here and look like a bug in the pipeline.
            await self.write_event(
                AudioStart(rate=RATE, width=WIDTH, channels=CHANNELS).event())
            self.started = True
        await self.write_event(AudioStop().event())
        self.started = False

    async def handle_event(self, event: Event) -> bool:
        if Describe.is_type(event.type):
            await self.write_event(self.info.event())
            return True

        if Synthesize.is_type(event.type):
            if self.streaming:
                # Home Assistant sends the whole message again after the chunks,
                # for servers that cannot stream. This one can, and has already
                # said it. A stand-in that got this wrong would hide the same
                # mistake in the real server.
                self.note("ignored-trailing-synthesize", "")
                return True
            text = Synthesize.from_event(event).text
            self.note("synthesize", text)
            for sentence in take_complete_sentences(text + " ")[0] or [text]:
                await self.speak(sentence)
            await self.finish()
            return True

        if SynthesizeStart.is_type(event.type):
            self.note("start", "")
            self.buffer = ""
            self.streaming = True
            return True

        if SynthesizeChunk.is_type(event.type):
            self.buffer += SynthesizeChunk.from_event(event).text
            sentences, self.buffer = take_complete_sentences(self.buffer)
            for sentence in sentences:
                await self.speak(sentence)
            return True

        if SynthesizeStop.is_type(event.type):
            if self.buffer.strip():
                await self.speak(self.buffer.strip())
            self.buffer = ""
            await self.finish()
            await self.write_event(SynthesizeStopped().event())
            self.streaming = False
            self.note("stop", "")
            return True

        return True


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--uri", default="tcp://127.0.0.1:10211")
    parser.add_argument("--journal", default="scratch/spoken.jsonl")
    args = parser.parse_args()

    info = Info(tts=[TtsProgram(
        name="fake", description="says nothing, writes it down", installed=True,
        version="1", attribution=Attribution(name="dev", url=""),
        supports_synthesize_streaming=True,
        voices=[TtsVoice(name="silence", description="silence", installed=True,
                         version="1", languages=["en"],
                         attribution=Attribution(name="dev", url=""))])])

    open(args.journal, "w").close()
    print(f"fake tts on {args.uri}, journal {args.journal}", flush=True)
    await AsyncServer.from_uri(args.uri).run(
        lambda *a, **k: Handler(info, args.journal, *a, **k))

asyncio.run(main())
