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
