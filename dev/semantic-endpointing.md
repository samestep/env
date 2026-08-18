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
