"""Detect wrong-state restores by their only reliable symptom: changed output.

At temperature 0 the same prompt must produce the same text. Each question is a
FRESH conversation, so each one forces the restore path -- exactly where a
checkpoint mix-up would show. Run on a known-good build to record a baseline,
then again after a change; any diff is a state bug, however good the latency
looks.
"""
import hashlib, json, sys, urllib.request

URL = "http://192.168.122.1:11434/api/chat"
MODEL = "qwen3.6:27b-mtp-q8_0"
SYS = ("You are a voice assistant for a home.\n" + "\n".join(
    f"- device_{i}: Device {i} ('Device {i}', {'on' if i % 3 else 'off'})"
    for i in range(300)))
QS = ["Which devices are off? Name the first three.",
      "What is device 7 called and what state is it in?",
      "Count the devices you can see, then say the number only.",
      "Repeat the state of device 12 exactly.",
      "List devices 20 through 24 with their states.",
      "What was the very first device in your list?",
      "Say the state of device 299.",
      "How many devices are listed in total?"]

out = {}
for q in QS:
    body = json.dumps({"model": MODEL, "think": False, "keep_alive": -1,
                       "messages": [{"role": "system", "content": SYS},
                                    {"role": "user", "content": q}],
                       "stream": False,
                       "options": {"temperature": 0, "seed": 1, "num_predict": 80}}).encode()
    r = urllib.request.Request(URL, body, {"Content-Type": "application/json"})
    d = json.load(urllib.request.urlopen(r, timeout=600))
    out[q] = d["message"]["content"].strip()

path = sys.argv[1]
json.dump(out, open(path, "w"), indent=1)
digest = hashlib.sha256(json.dumps(out, sort_keys=True).encode()).hexdigest()[:16]
print(f"wrote {path}  digest {digest}")
for q, a in out.items():
    print(f"  {q[:44]:46} -> {a[:58]!r}")
