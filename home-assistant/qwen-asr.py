"""Expose native Transformers Qwen3-ASR to Home Assistant over Wyoming."""

import argparse
import asyncio
import os
import logging
import re
import time
from contextlib import suppress
from functools import partial
from pathlib import Path

from ha_vocabulary import RuntimeVocabulary, normalize

from wyoming.asr import Transcript
from wyoming.audio import AudioChunk, AudioStart, AudioStop
from wyoming.error import Error
from wyoming.info import AsrModel, AsrProgram, Attribution, Describe, Info
from wyoming.server import AsyncEventHandler, AsyncServer

LOGGER = logging.getLogger("qwen-asr")
MODEL = "Qwen/Qwen3-ASR-1.7B-hf"
MAX_AUDIO_BYTES = 16000 * 2 * 120


def command(text):
    """Recognize only complete turn-on/off commands; leave general speech alone."""
    text = normalize(text)
    match = re.fullmatch(r"turn (on|off) (?:the )?(.+)", text)
    if match:
        return match[1], match[2]
    match = re.fullmatch(r"turn (?:the )?(.+) (on|off)", text)
    if match:
        return match[2], match[1]
    return None


def select_transcript(candidates, vocabulary):
    """Prefer an unambiguous known-device command without changing its action.

    The top candidate supplies the action. If it already names a device, or is
    general speech, preserve it. Otherwise select the highest ranked candidate
    with that action, only when all such known-device candidates agree on the
    device. Return an actual generated sentence, never synthesize a command.
    """
    if not candidates:
        return "", 0
    top = candidates[0]
    intent = command(top)
    names = vocabulary.entities
    if intent is None or intent[1] in names:
        return top, 1
    if set(intent[1].split()) & {"and", "or", "then", "not", "but", "except"}:
        return top, 1
    matches = []
    for rank, text in enumerate(candidates[1:], 2):
        alternative = command(text)
        if alternative and alternative[0] == intent[0] and alternative[1] in names:
            matches.append((rank, text, names[alternative[1]]))
    if matches and len(set().union(*(item[2] for item in matches))) == 1:
        rank, text, _ = matches[0]
        return text, rank
    return top, 1


class Recognizer:
    def __init__(self, vocabulary, beam_size=5):
        self.vocabulary = vocabulary
        self.beam_size = beam_size
        import torch
        from transformers import AutoModelForMultimodalLM, AutoProcessor

        if not torch.cuda.is_available():
            raise RuntimeError("CUDA is unavailable; check the NVIDIA driver")
        LOGGER.info("Loading %s on %s", MODEL, torch.cuda.get_device_name(0))
        self.processor = AutoProcessor.from_pretrained(MODEL)
        self.model = AutoModelForMultimodalLM.from_pretrained(
            MODEL, dtype=torch.bfloat16
        ).to("cuda:0").eval()
        self.lock = asyncio.Lock()
        LOGGER.info("Model loaded; beam size %d; vocabulary from Home Assistant",
                    self.beam_size)

    def transcribe(self, pcm):
        import numpy as np
        import torch

        audio = np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768.0
        started = time.monotonic()
        vocabulary = self.vocabulary.snapshot
        with torch.inference_mode():
            # Let Qwen emit its no-language/no-speech result. Forcing English
            # bypasses that decision and can turn silence into vocabulary text.
            inputs = self.processor.apply_transcription_request(
                audio=audio, language=None, prompt=vocabulary.prompt
            ).to(self.model.device, self.model.dtype)
            output = self.model.generate(
                **inputs, max_new_tokens=1024, do_sample=False,
                num_beams=self.beam_size, num_return_sequences=self.beam_size,
            )
            generated = output[:, inputs["input_ids"].shape[1]:]
            candidates = [text.strip() for text in self.processor.decode(
                generated, return_format="transcription_only"
            )]
            text, rank = select_transcript(candidates, vocabulary)
        LOGGER.info("Transcribed %.2fs of audio in %.2fs", len(audio) / 16000,
                    time.monotonic() - started)
        if rank > 1:
            LOGGER.info("Selected candidate %d: %r (first choice: %r)",
                        rank, text, candidates[0])
        LOGGER.debug("Transcription candidates: %s", candidates)
        return text


class Handler(AsyncEventHandler):
    def __init__(self, recognizer, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.recognizer = recognizer
        self.audio = None

    async def handle_event(self, event):
        if Describe.is_type(event.type):
            attribution = Attribution(name="Qwen", url="https://huggingface.co/" + MODEL)
            model = AsrModel(name=MODEL, attribution=attribution, installed=True,
                             description="Qwen3-ASR 1.7B, CUDA, English",
                             version=None, languages=["en"])
            await self.write_event(Info(asr=[AsrProgram(
                name="qwen3-asr", attribution=attribution, installed=True,
                description="Qwen3-ASR", version="1", models=[model]
            )]).event())
        elif AudioStart.is_type(event.type):
            start = AudioStart.from_event(event)
            if (start.rate, start.width, start.channels) != (16000, 2, 1):
                await self.write_event(Error(text="Expected 16 kHz, 16-bit mono PCM",
                                             code="invalid-audio").event())
                return False
            self.audio = bytearray()
        elif AudioChunk.is_type(event.type):
            if self.audio is None:
                return False
            self.audio.extend(AudioChunk.from_event(event).audio)
            if len(self.audio) > MAX_AUDIO_BYTES:
                await self.write_event(Error(text="Audio exceeds two minutes",
                                             code="audio-too-long").event())
                return False
        elif AudioStop.is_type(event.type):
            pcm, self.audio = self.audio, None
            if pcm is None or len(pcm) % 2:
                await self.write_event(Error(text="Invalid audio stream",
                                             code="invalid-audio").event())
                return False
            try:
                if not pcm:
                    text = ""
                else:
                    # Serialize GPU use across connections. Shield the worker so
                    # cancellation cannot release the lock during inference.
                    async with self.recognizer.lock:
                        task = asyncio.create_task(asyncio.to_thread(
                            self.recognizer.transcribe, bytes(pcm)))
                        try:
                            text = await asyncio.shield(task)
                        except asyncio.CancelledError:
                            await task
                            raise
                await self.write_event(Transcript(text=text, language="en").event())
            except Exception:
                LOGGER.exception("Transcription failed")
                await self.write_event(Error(text="Qwen transcription failed; see service logs",
                                             code="transcription-failed").event())
                return False
        return True


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--uri", default="tcp://127.0.0.1:10310")
    parser.add_argument("--home-assistant-url", default="http://127.0.0.1:8123")
    parser.add_argument("--home-assistant-token-file", type=Path, default=Path(
        os.environ.get("CREDENTIALS_DIRECTORY", "/run/credentials/wyoming-qwen-asr.service")
    ) / "qwen-asr-home-assistant-token")
    parser.add_argument("--vocabulary-refresh-seconds", type=float, default=60)
    parser.add_argument("--beam-size", type=int, default=5)
    parser.add_argument("--check-vocabulary", action="store_true",
                        help="Fetch and log Assist names, then exit without loading the model")
    args = parser.parse_args()
    if args.beam_size < 1 or args.vocabulary_refresh_seconds <= 0:
        parser.error("Beam size and vocabulary refresh interval must be positive")
    vocabulary = RuntimeVocabulary(
        args.home_assistant_url, args.home_assistant_token_file,
        args.vocabulary_refresh_seconds,
    )
    await vocabulary.refresh()
    if args.check_vocabulary:
        raise SystemExit(1 if vocabulary.error else 0)
    recognizer = Recognizer(vocabulary, args.beam_size)
    refresh_task = asyncio.create_task(vocabulary.run())
    try:
        LOGGER.info("Listening on %s", args.uri)
        await AsyncServer.from_uri(args.uri).run(partial(Handler, recognizer))
    finally:
        refresh_task.cancel()
        with suppress(asyncio.CancelledError):
            await refresh_task


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
