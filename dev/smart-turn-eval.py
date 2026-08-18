"""Evaluate Smart Turn v3 on its own labelled test set, real recordings only.

Validates the preprocessing (a wrong mel pipeline shows up as chance accuracy)
and, more usefully, reports the subset with a mid-utterance filler -- someone
pausing mid-thought, which is the case a silence threshold cannot handle.
"""
import io, sys
import numpy as np, onnxruntime as ort, pyarrow.parquet as pq, soundfile as sf
from transformers import WhisperFeatureExtractor

SR = 16000
fe = WhisperFeatureExtractor(chunk_length=8)
sess = ort.InferenceSession("/home/agent-amd64/models/smart-turn/smart-turn-v3.2-cpu.onnx",
                            providers=["CPUExecutionProvider"])

def predict(a):
    if len(a) > 8*SR: a = a[-8*SR:]
    inp = fe(a, sampling_rate=SR, return_tensors="np", padding="max_length",
             max_length=8*SR, truncation=True, do_normalize=True)
    f = np.expand_dims(inp.input_features.squeeze(0).astype(np.float32), 0)
    return sess.run(None, {"input_features": f})[0][0].item()

tbl = pq.read_table(sys.argv[1] if len(sys.argv) > 1
                    else "/home/agent-amd64/models/smart-turn/data/t0.parquet")
cols = tbl.column_names
print("columns:", cols)
n = tbl.num_rows
limit = int(sys.argv[2]) if len(sys.argv) > 2 else 400
rows = tbl.to_pylist()
real = [r for r in rows if not r.get("synthetic") and r.get("language") == "eng"]
print(f"{n} rows, {len(real)} real English; scoring up to {limit}\n")

groups = {}
for r in real[:limit]:
    audio = r["audio"]
    data, sr = sf.read(io.BytesIO(audio["bytes"]), dtype="float32")
    if data.ndim > 1: data = data.mean(axis=1)
    p = predict(data)
    correct = (p > 0.5) == bool(r["endpoint_bool"])
    for key in ("all", "midfiller" if r.get("midfiller") else "no filler",
                "complete" if r["endpoint_bool"] else "incomplete"):
        g = groups.setdefault(key, [0, 0]); g[0] += correct; g[1] += 1

print(f"{'subset':>12}  {'n':>5}  {'accuracy':>9}")
for k in ("all", "complete", "incomplete", "midfiller", "no filler"):
    if k in groups:
        c, t = groups[k]
        print(f"{k:>12}  {t:5d}  {c/t*100:8.1f}%")
