# Semantic endpointing

**Result: 1406 ms -> 600 ms** from the last sample of speech to the assistant's
answer, and it now keeps listening through a mid-sentence pause, which no
setting could do before.

## What changed

| | |
|---|---|
| Turn detection | Smart Turn v3 decides whether a pause is final, so `silence_seconds` no longer has to be long enough to forgive one |
| `silence_seconds` | 0.7 -> 0.25 by default, 0.1 available; every 100 ms off it is 100 ms off the answer |
| Speculative transcription | transcribes a snapshot taken when speech stops, during the wait, instead of after it |
| Speculative conversation | runs the model on that transcript too, holding side effects and speech until the turn is confirmed |
| Streaming synthesis | Kokoro is fed text as it is generated, so the first sentence is spoken while the last is still being written |
| Model | `ornith:35b-q4_K_M` scored 45/45 against 38/45 for the incumbent, and is faster |

## The one thing to understand

Silence cannot tell "still thinking" from "finished" -- they are acoustically
identical and only the words differ. So with a silence threshold alone, how fast
the assistant answers and how long a pause it forgives are **the same number**,
and every setting is a compromise between them. A turn model separates them: the
threshold governs the common case, the model holds the turn open when the
utterance sounds unfinished.

## Try it

    dev/run-ha.sh                       # the development instance
    dev/turn-test.py <clip>             # does it hold a pause?
    dev/silence-sweep.py                # latency against pause tolerance
    dev/stage-breakdown.py              # where the time goes
    dev/eval.py 3 <model>...            # scenario scores, state reset each run
    dev/model-compare.py                # models end to end
    dev/smart-turn-probe.py <clip>      # the model's opinion, cut by cut

Voice tests need a transcriber in the VM:

    $(nix build --no-link --print-out-paths nixpkgs#wyoming-faster-whisper)/bin/wyoming-faster-whisper \
      --model tiny-int8 --language en --uri tcp://127.0.0.1:10300 \
      --data-dir ~/ha-dev/whisper --download-dir ~/ha-dev/whisper

## Still open

- **Recordings of the person who will use it.** Everything here is public data
  and text-to-speech. The 6.1% of unfinished utterances the model cuts off at
  threshold 0.9 is the number that matters, and it cannot be checked against a
  corpus that does not contain your voice, your room or your phrasing.
- **Speculating past transcription** is now done; see below. Tool calls that
  would change something are held mid-call rather than abandoned, so a guess
  that turns out right keeps the prefill and the tokens that chose the tool.
- **Streaming speech synthesis** is done and verified on the host; see below.
- **Switching the live assistant to ornith.** Left deliberately for a person:
  the eval is 15 scenarios against demo entities, not a house.

---

No silence threshold can tell "still thinking" from "finished": they are
acoustically identical and only the words differ. Every setting we can reach
trades response speed against how long a pause is tolerated, one for one.

A turn-detection model breaks that trade. It reads the utterance and predicts
whether the speaker is done, so a short silence threshold can be used for the
common case while genuine mid-thought pauses are rescued.

## Smart Turn v3 looks like the right model

`pipecat-ai/smart-turn-v3` on Hugging Face, BSD-2-Clause. Whisper Tiny encoder
plus a linear head, 8M parameters, 8 MB int8 ONNX. It reads the waveform, not a
transcript, so it needs no extra speech-to-text pass. Published accuracy 92.6%
over 31,527 samples across 23 languages.

This is the same shape LiveKit and Pipecat both use: a cheap VAD for
speech/silence, and a separate end-of-utterance model on top.

Interface: `input_features` `[batch, 80, 800]` — a Whisper mel spectrogram of
the **last 8 seconds** — and one output which is already a probability, not a
logit. Preprocessing is `WhisperFeatureExtractor(chunk_length=8)` with
`do_normalize=True`.

## It works, on real speech

Sweeping cut points through the JFK sample:

    cut (s)  P(complete)
        2.5        0.864   "And so my fellow Americans,"   clause end
        3.0        0.568
        4.0        0.035   mid-clause
        7.5        0.028   mid-clause
       10.5        0.904   "...do for your country."       sentence end
       11.0        0.625

Clause and sentence ends score high, mid-clause scores near zero. Inference is
~30 ms on this VM's CPU, unoptimised.

## Text-to-speech cannot test this

Piper clips scored 0.93-0.99 whether the sentence was complete or truncated
mid-phrase. That is not the model failing: asked to say "Turn on the kitchen",
a synthesiser produces the falling intonation of a finished sentence, because it
does not know the text is a fragment. The model reads prosody, so a TTS fragment
is indistinguishable from a TTS sentence.

**Validation needs real recordings**, ideally of the person who will use it,
pausing naturally mid-request. `ldc.wav`, a single read TIMIT sentence, also
scores 0.96+ at every cut, so read speech may be a poor test too.

## What it buys

Today latency and pause tolerance are the same number: 0.25 s means both a
376 ms response and being cut off after a 250 ms pause. With a turn model the
short threshold governs the common case, and the model holds the turn open when
the utterance sounds unfinished -- fast when you are done, patient when you are
not.


## Measured on the model's own labelled test set

`pipecat-ai/smart-turn-data-v3.1-test` carries `endpoint_bool`, plus `synthetic`
and `midfiller` flags. Filtering to **real, non-synthetic English** recordings
(607 of them in one shard, 312 complete and 295 not):

**93.2% accuracy**, against the 92.63% published across all languages. That also
validates the preprocessing port -- a wrong mel pipeline reads as chance.

The two errors cost very different amounts, so the threshold matters:

| threshold | cut off mid-thought | made to wait when done |
|---|---|---|
| 0.3 | 19.7% | 1.0% |
| 0.5 (default) | 14.6% | 1.9% |
| 0.7 | 11.2% | 3.8% |
| 0.8 | 8.8% | 4.8% |
| 0.9 | 6.1% | 8.7% |
| 0.95 | 2.4% | 13.1% |
| 0.98 | 0.7% | 32.1% |

Being cut off mid-thought is the failure worth avoiding; being made to wait costs
one extra increment. Today *every* pause longer than `silence_seconds` cuts you
off, so even the default threshold is a large improvement, and ~0.9 looks like a
sensible operating point.

## The verdict does not drift, so the design needs a cap

Appending silence to unfinished utterances barely moves the score:

    +0 ms   median P 0.033
    +500 ms median P 0.044
    +2000 ms median P 0.060

So re-checking as silence accumulates will not converge on ending the turn by
itself. Something that sounds unfinished stays unfinished, and an utterance
someone simply trails off from would hold the turn open forever. The design
needs an explicit maximum.

## Design

1. Silero detects silence as now, with `silence_seconds` set low (~0.25 s).
2. On expiry, run Smart Turn over the last 8 s of buffered audio (~30 ms).
3. `P(complete) > 0.9` -> end the turn. Total ~280 ms.
4. Otherwise extend by another increment and re-check.
5. Cap the total extension (~2-3 s) and end regardless, because of the drift
   result above.

This is the shape Pipecat and LiveKit both use. It decouples the two numbers
that are currently the same: a short threshold governs the common case, and the
model holds the turn open only when the utterance actually sounds unfinished.


## Working end to end

Streaming a real recording in real time through the dev instance, with no
artificial pause -- the speaker's own pauses are the test:

    silence only, 0.25 s     ended 2.5s  heard: ' And so my fellow Americans'
    silence only, 0.70 s     ended 3.0s  heard: ' And so my fellow Americans!'
    turn detection, 0.25 s   ended 5.2s  heard: ' And so my fellow Americans, ASK NOT!'

The model recognised the pause after "Americans," as unfinished and kept
listening, at the *shorter* silence threshold. It still stops at 5.2 s because
`turn_max_seconds` was 2.0 and this speaker pauses for dramatic effect -- which
is the cap doing its job.

`dev/turn-test.py` runs this. It needs a speech-to-text engine in the VM:

    nix build --no-link --print-out-paths nixpkgs#wyoming-faster-whisper
    .../bin/wyoming-faster-whisper --model tiny-int8 --language en \
      --uri tcp://127.0.0.1:10300 --data-dir ~/ha-dev/whisper \
      --download-dir ~/ha-dev/whisper

`demo_stt` cannot stand in for it: it accepts only stereo, and the pipeline
sends mono.

## A bug worth remembering

`VoiceCommandSegmenter.process()` calls `reset()` as it reports the command
finished, which clears `in_command`. Granting another silence window therefore
has to restore that flag as well as the counter -- the silence counter only
decrements *inside* a command, so without it the segmenter sits waiting for
speech that may never come and the turn never ends at all. The symptom was runs
that hung until the 60 s pipeline timeout, with the model logging "keep
listening" correctly each time.


## The payoff: latency and pause tolerance finally separate

Sweeping `silence_seconds` with and without the turn model, measuring both
things that matter -- when a *finished* utterance ends, and whether a
*mid-sentence* pause survives:

| silence_seconds | turn | finished utterance ends | mid-sentence pause |
|---|---|---|---|
| 0.70 | off | 3.6 s | cut short |
| 0.70 | on | 3.7 s | **held** |
| 0.40 | off | 3.3 s | cut short |
| 0.40 | on | 3.4 s | **held** |
| 0.25 | off | 3.1 s | cut short |
| 0.25 | on | 3.2 s | **held** |
| 0.15 | off | 3.0 s | cut short |
| 0.15 | on | 3.1 s | **held** |
| 0.10 | off | 3.0 s | cut short |
| **0.10** | **on** | **3.1 s** | **held** |

Without the model, every setting cuts the pause short -- the tolerance *is* the
threshold. With it, the pause is held at every setting, and the threshold is
free to be small. `silence_seconds` 0.7 -> 0.1 takes **600 ms** off a finished
utterance while pauses keep working, and the model itself costs about 100 ms.

Recommended: `silence_seconds` 0.1-0.15 with `turn_detection` on. That is
roughly 200 ms from end of speech to decision, against 789 ms measured for
silence alone at 0.7, and it is inside the 200 ms band of human turn-taking.


## End to end

Full pipeline, audio in to answer out, timed from the last sample of speech,
through the real conversation agent on the host:

    before: silence 0.7, no turn model     1408 ms   'No, the bed light is off.'
    after:  silence 0.1, turn model         824 ms   'No, the bed light is off.'

**584 ms**, same answer. `dev/e2e-compare.py` runs it.


## Model choice, re-tested

End to end from the last sample of speech, with the turn model on and
`silence_seconds` 0.1:

| model | question answered from the prompt | control command, needs a tool call |
|---|---|---|
| qwen3.8:27b-mtp-q8_0 | 817 ms | 1503 ms |
| qwen3.6:35b-a3b-q4_K_M | 717 ms | 1251 ms |
| ornith:35b-q4_K_M | 713 ms | **1116 ms** |

**No CUDA fault in 18 tool-call runs across the two MoE models.** That fault --
an illegal memory access during constrained decoding of tool calls with array or
enum parameters -- is what disqualified qwen35moe, on ollama 0.32.3. We run
0.32.13. It appears resolved, which reopens the faster models.

Caveats before switching: `qwen3.6:35b-a3b` answered "I am unable to turn on the
kitchen lights" where ornith turned it on, so speed is not the only axis and this
needs the scenario eval rather than a latency script. And the replies above are
not strictly comparable because the light's state carried between runs -- one
model reported "already on". Reset entity state between runs when comparing
behaviour rather than timing.


## Quality: ornith is the one to use

`dev/eval.py` runs 15 scenarios against the development instance, resetting
entity state before *every* run so a light left on by one scenario cannot make
the next look correct. Three repetitions each, 45 runs per model:

| model | scenarios passed | median intent |
|---|---|---|
| qwen3.8:27b-mtp-q8_0 (current) | 38/45 | 441 ms |
| qwen3.6:35b-a3b-q4_K_M | 39/45 | 466 ms |
| **ornith:35b-q4_K_M** | **45/45** | 678 ms |

ornith is perfect where the others miss six or seven. Its higher median here is
partly an artefact of being correct: "I am unable to turn on the kitchen lights"
returns faster than actually turning it on. On real audio end to end it is the
*fastest* of the three -- 713 ms against 817 for a question, 1116 against 1503
for a command.

`<|fim_pad|>` is a single special token in all three vocabularies, so the cache
boundary carries over unchanged.

Recommendation: switch the conversation agent to `ornith:35b-q4_K_M`. Left for a
person to decide, because the eval is 15 scenarios against demo entities rather
than a real house, and the assistant's manner of speaking is a matter of taste.


## Defaults

The settings above are no use if a real satellite never passes them, so the
patch changes what the defaults are:

- `turn_detection` defaults to **on**
- `silence_seconds` defaults to **0.25**, upstream 0.7
- `VadSensitivity` becomes relaxed 0.7 / default 0.25 / aggressive 0.1,
  upstream 1.25 / 0.25 / 0.7

Those are only safe *because* the model supplies the pause tolerance. Without it,
`silence_seconds` has to be both how fast the assistant answers and how long a
pause it forgives, which is why upstream's numbers are so long.

Measured with no per-run settings at all: **940 ms** from end of speech to
answer, against 1408 ms on the old defaults. Selecting "aggressive" takes it to
~824 ms.


## Where the time goes, and speculative transcription

Per stage, from the last sample of speech, with the turn model on:

    VAD + turn model decided       243 ms
    speech-to-text finished        454 ms   (+211)
    answer ready                   837 ms   (+383)

The wait for silence and the transcription are both dead time, and they were
consecutive for no reason. `speculative_stt` takes a snapshot the moment speech
stops and transcribes *that* during the wait, so the text is ready when the turn
is confirmed over. If the speaker resumes, the snapshot is cancelled and the
normal path is used.

    speculative stt off       838 ms
    speculative stt on        720 ms

118 ms, bounded by how much wait there is to hide behind. It costs one extra
transcription of audio that is thrown away when the speaker turns out not to
have finished, which is cheap: whisper tiny on CPU.

Verified that holding a pause still works with it on -- the JFK clip still
reaches "ASK NOT", so the snapshot really is discarded when speech resumes.

**The snapshot needs padding.** Ending it on the last phoneme, with none of the
silence the full stream would carry, changes what the transcriber hears: across
six clips two came out different, one of them a real mishearing ("set the bad
light" for "set the bed light") and one only capitalisation. Appending 250 ms of
silence to the snapshot makes all six identical. Worth checking again if the
speech-to-text engine changes, because this is a property of the engine, not of
the idea.


## Altogether

From the last sample of speech to the answer, through the real conversation
agent:

| configuration | question | control command |
|---|---|---|
| before any of this | 1406 ms | 2026 ms |
| turn model + speculative transcription | 717 ms | 774 ms |
| + ornith as the agent | **600 ms** | 1013 ms |

**1406 -> 600 ms on a question, 2.3x.** And it now holds a mid-sentence pause,
which no setting could do before.

The command column is not trustworthy: entity state carries between runs, so a
model that says "already on" looks faster than one that actually switches the
light. Compare behaviour with `dev/eval.py`, which resets state before every
run, not with a latency script.


## Streaming speech synthesis

Nothing was spoken until the last token of the reply was generated, because
Kokoro did not advertise `supports_synthesize_streaming` and Home Assistant will
not stream text into an engine that does not.

It turned out the hard part was already done. `kokoro-wyoming` **already** splits
text into sentences and emits audio for each as it is synthesised:

    sentences = split_into_sentences(text)
    for sentence in sentences:
        stream = self.kokoro.create_stream(sentence, ...)
        if i == 0:
            await self.write_event(AudioStart(...).event())
        async for audio, sample_rate in stream:
            ...AudioChunk...

Only the *input* side was missing: it waited for one complete `Synthesize` event.
`kokoro-wyoming-streaming.patch` adds `SynthesizeStart` / `SynthesizeChunk` /
`SynthesizeStop`, buffering text and synthesising each sentence as soon as it is
finished. So the model does not need to stream -- Kokoro synthesises a whole
utterance at once -- it just has to be fed sooner.

`take_complete_sentences` only hands over text up to the last sentence-ending
punctuation, so a sentence is never synthesised from a fragment that more text
would have changed.

`dev/kokoro-stream-test.py` drives the handler with a stub synthesiser, since
building the real one needs onnxruntime with CUDA. Feeding it a reply the way a
language model produces it:

    after 'The bed '          synthesised=[]                          audio chunks=0
    after 'light is off. '    synthesised=['The bed light is off.']    audio chunks=1
    after 'The kitchen '      synthesised=['The bed light is off.']    audio chunks=1
    after 'lights are on'     synthesised=['The bed light is off.']    audio chunks=1
    after '. Anything else?'  synthesised=[all three]                  audio chunks=3

    event order: audio-start ... audio-stop synthesize-stopped

The first sentence is spoken while the third is still being generated. The
longer the reply, the more this saves, and it is the only change here that
attacks time-to-*first-audio* rather than time-to-answer.

### Verified on the host

`run-start` carries `tts_output.stream_response`, which is true only when the
synthesiser takes streamed input *and* the agent produces streamed output, so
the question needs no guessing:

    stream_response = True

Fetching the audio from the moment the URL exists, and timing the first byte
against the moment generation finished:

| reply | first audio | generation done | speaking starts |
|---|---|---|---|
| "Is the bed light on?" | 516 ms | 381 ms | 135 ms *after* |
| three sentences | 1054 ms | 2535 ms | **1482 ms before** |
| eight sentences | 748 ms | 5500 ms | **4752 ms before** |

A one-sentence answer gains nothing -- there is no later sentence to overlap
with, and synthesis still has to happen. Everything longer gains roughly the
whole of its own generation time. Reproduce with `scratch/host-tts-firstbyte.py`.

### Every reply was being synthesised twice

Home Assistant sends `SynthesizeStart`, then the chunks, and then the whole
message again as a plain `Synthesize` -- commented in `wyoming/tts.py` as "for
backwards compatibility", for servers that cannot stream. The patched server
fell through to its ordinary `Synthesize` handler for that, so it said
everything a second time and spent twice the GPU on it.

The stub test had not caught it because it sent only the events the streaming
path cares about. It now performs the exchange Home Assistant actually performs,
trailing `Synthesize` included, which is the version worth keeping: the bug was
not in the logic under test but in the half of the protocol the test omitted.

## Speculating on the conversation, not just the transcription

Transcribing early leaves the *model* idle for the rest of the wait, and the
model is the slower of the two. So the conversation now starts on the
speculative transcript as well, and everything it produces is held until the
turn is confirmed:

| what | how it is held |
|---|---|
| pipeline events | buffered and replayed in order at commit |
| speech | the stream is not handed to the synthesiser until commit |
| tools that read | run immediately -- a wrong one wastes milliseconds |
| tools that act | block inside `llm.APIInstance.async_call_tool` |

**Held, not abandoned.** The prefill and the tokens that chose the tool are
still valid if the guess was right, which it usually is, so a paused call costs
nothing and resumes on commit. Abandoning would throw away the most expensive
part of the work to save nothing.

`llm.Tool.reads_only` says which tools may run on a guess. It defaults to
*acts*, because the two mistakes do not cost the same: a needless read wastes a
few milliseconds, a needless action cannot be undone. Only `GetLiveContext`,
`GetDateTime`, `calendar_get_events`, `todo_get_items` and the read-only intents
are marked.

Discard is nearly free, which is what makes the whole thing safe.
`conversation.async_get_chat_log` builds on a copy of the history and writes it
back only *after* the block it guards finishes -- so cancelling the task leaves
nothing behind. `async_get_chat_session` does the same. Neither needed changing.

### What it is worth

Speculation cannot remove the wait itself: the answer still must not arrive
before the speaker is known to have finished. What it removes is the work that
used to happen *after* the wait. So the number to look at is not the saving at
one setting, it is how flat the curve becomes.

    question                          command
    silence     off     on            silence     off     on
       0.10     785     753              0.10    1477    1379
       0.25     787     760              0.25    1476    1421
       0.70    1244     838              0.70    1887    1370

Median ms from the last sample of speech to the answer, four runs a cell,
`dev/speculation-sweep.py`. With speculation on, latency barely depends on the
wait at all: 753-838 ms across the whole range for a question, 1370-1421 ms for
a command. Without it, going from 0.25 to 0.7 costs 457 ms and 411 ms.

**So pause tolerance is close to free now.** The default stays at 0.25 s, since
the turn model already holds mid-sentence pauses and there is no reason to make
a finished utterance wait longer. But 0.7 s costs about 80 ms instead of about
460 ms, which makes it a reasonable thing to reach for if the model turns out to
cut you off -- a pause shorter than the threshold is never submitted to it at
all.

The saving is smaller here than it will be on the host, because this VM
transcribes in ~211 ms against the host's 94-167 ms, and the transcription has
to finish before the conversation can start on it. The idle left inside a
250 ms wait is whatever the transcriber does not use.

### Checking it does not act on a guess

`dev/speculation-safety.py` plays a complete command, a pause, then more speech
-- the shape of someone who was not finished -- with `turn_threshold` at 1.0 so
the pause is held however final the fragment sounds. Counting states is not
enough, because the full utterance contains that command too and the light ends
up off either way. What separates them is how many times the service was called:

    heard: ' Turn off the ceiling lights.  Is the kitchen light on right now?'
    service calls: ['homeassistant.turn_off', 'light.turn_off']
    light.turn_off called 1 time(s)

and in the log, the held call is dropped rather than released:

    holding tool call HassTurnOff until the turn is confirmed
    abandoning speculative conversation:  Turn off the ceiling lights.
    speculating on:  Turn off the ceiling lights.  Is the kitchen light on...
    holding tool call HassTurnOff until the turn is confirmed
    committing speculative conversation, releasing held HassTurnOff

`dev/speculation-speech.py` checks the other half, that a guess is never spoken,
against `dev/fake-tts.py` -- a synthesiser that says nothing and writes down what
it was asked to say, since Kokoro needs CUDA and that question does not.

### Two things that only a real synthesiser in the loop would have found

**Home Assistant caches speech.** These clips draw the same few replies over and
over, so runs were served from the cache and the synthesiser was never asked
anything -- which looks exactly like "nothing was spoken". The test clears the
cache between cases now.

**A race between commit and the start of streaming.** Home Assistant only starts
streaming text into the synthesiser once a reply looks long enough to be worth
it. That can happen *after* commit, and the first version stored the stream
whenever it was a speculation -- so a stream created after commit was stored for
a commit that had already happened, and nobody wired it. Home Assistant then
skipped `async_set_message`, believing a stream was set, and the reply was never
spoken. The decision is on the gate now, the same condition the event buffer
uses, not on "is this a speculation".
