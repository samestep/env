"""Score every real English sample once, then sweep the decision threshold.

The two errors are not equal. Calling an unfinished utterance complete cuts the
speaker off mid-thought. Calling a finished one incomplete just waits a little
longer. So the threshold should be biased towards waiting.
"""
import io, json, os, sys
import numpy as np, onnxruntime as ort, pyarrow.parquet as pq, soundfile as sf
from transformers import WhisperFeatureExtractor

SR = 16000
CACHE = "/home/agent-amd64/models/smart-turn/scores.json"
fe = WhisperFeatureExtractor(chunk_length=8)
sess = ort.InferenceSession("/home/agent-amd64/models/smart-turn/smart-turn-v3.2-cpu.onnx",
                            providers=["CPUExecutionProvider"])

def predict(a):
    if len(a) > 8*SR: a = a[-8*SR:]
    inp = fe(a, sampling_rate=SR, return_tensors="np", padding="max_length",
             max_length=8*SR, truncation=True, do_normalize=True)
    f = np.expand_dims(inp.input_features.squeeze(0).astype(np.float32), 0)
    return sess.run(None, {"input_features": f})[0][0].item()

if os.path.exists(CACHE):
    scored = json.load(open(CACHE))
else:
    scored = []
    for shard in sys.argv[1:]:
        for r in pq.read_table(shard).to_pylist():
            if r.get("synthetic") or r.get("language") != "eng":
                continue
            d, _ = sf.read(io.BytesIO(r["audio"]["bytes"]), dtype="float32")
            if d.ndim > 1: d = d.mean(axis=1)
            scored.append({"p": predict(d), "complete": bool(r["endpoint_bool"]),
                           "dataset": r["dataset"]})
    json.dump(scored, open(CACHE, "w"))

comp = [s["p"] for s in scored if s["complete"]]
inc = [s["p"] for s in scored if not s["complete"]]
print(f"scored {len(scored)} real English samples: {len(comp)} complete, {len(inc)} incomplete\n")
print(f"{'threshold':>10} {'cut off mid-thought':>21} {'made to wait when done':>24}")
for thr in (0.3, 0.5, 0.7, 0.8, 0.9, 0.95, 0.98, 0.99):
    cut = sum(1 for p in inc if p > thr) / len(inc) * 100      # said complete, was not
    wait = sum(1 for p in comp if p <= thr) / len(comp) * 100  # said incomplete, was not
    print(f"{thr:>10} {cut:>20.1f}% {wait:>23.1f}%")
