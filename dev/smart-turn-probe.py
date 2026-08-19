"""Does Smart Turn v3 tell a finished utterance from a mid-sentence one?

Sweeps cut points through a recording and prints P(turn complete) at each.
High scores should land on clause and sentence ends, low ones mid-clause.

Needs real speech: text-to-speech gives a *fragment* the falling intonation of
a finished sentence, because the synthesiser does not know it is a fragment,
and this model reads prosody. Piper clips score 0.93-0.99 whether complete or
truncated, which says nothing about the model.

  nix shell --impure --expr 'with import <nixpkgs> {}; [ (python3.withPackages
    (ps: [ ps.onnxruntime ps.transformers ps.numpy ])) ffmpeg ]' \
    --command python3 dev/smart-turn-probe.py <audio-file>
"""
import subprocess
import numpy as np, onnxruntime as ort
from transformers import WhisperFeatureExtractor
SR = 16000
fe = WhisperFeatureExtractor(chunk_length=8)
sess = ort.InferenceSession("/home/agent-amd64/models/smart-turn/smart-turn-v3.2-cpu.onnx",
                            providers=["CPUExecutionProvider"])
def pcm(p):
    raw = subprocess.run(["ffmpeg","-v","error","-i",p,"-ar",str(SR),"-ac","1",
                          "-f","f32le","-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).copy()
def predict(a, tail_ms=300):
    a = np.concatenate([a, np.zeros(SR*tail_ms//1000, dtype=np.float32)])
    if len(a) > 8*SR: a = a[-8*SR:]
    inp = fe(a, sampling_rate=SR, return_tensors="np", padding="max_length",
             max_length=8*SR, truncation=True, do_normalize=True)
    f = np.expand_dims(inp.input_features.squeeze(0).astype(np.float32), 0)
    return sess.run(None, {"input_features": f})[0][0].item()

import sys
a = pcm(sys.argv[1] if len(sys.argv) > 1 else "jfk.wav")
print()
print(f"{'cut (s)':>8}  {'P(complete)':>11}  bar")
for ms in range(1000, int(len(a)/SR*1000)+1, 500):
    p = predict(a[:SR*ms//1000])
    print(f"{ms/1000:8.1f}  {p:11.3f}  {'#'*int(p*40)}")
