# Semantic endpointing

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
