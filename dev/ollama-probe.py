#!/usr/bin/env python3
"""Measure prompt-prefix caching and generation speed on any ollama.

    OLLAMA_URL=http://127.0.0.1:11434 python3 dev/ollama-probe.py qwen3.8:27b-mtp-q8_0

Reports three things:
  fresh conversation  -- a new conversation sharing only the cached prefix, which
                         is what every voice command looks like
  follow-up turn      -- appending to the conversation already in the slot
  generation          -- tokens per second

Read prompt_eval_duration only. prompt_eval_count always reports the whole
prompt, reused or not.

Nothing else may talk to this ollama while it runs: one other request replaces
the slot contents and the next measurement then shares nothing with it.
"""
import json, os, statistics, sys, urllib.request

URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434") + "/api/chat"
MODEL = sys.argv[1] if len(sys.argv) > 1 else "qwen3.8:27b-mtp-q8_0"

# Shaped like Home Assistant's: a preamble plus a long entity table. The size and
# the fact that it is byte-identical across conversations are what matter.
SYSTEM = (
    "You are a voice assistant for a home. Answer in one or two short sentences, "
    "in plain spoken language, with no markdown and no lists.\n\n"
    "An overview of the areas and the devices in this smart home:\n"
) + "\n".join(
    f"- device_{i}: Device {i} ('Device {i}', {'on' if i % 3 else 'off'})"
    for i in range(300))

QUESTIONS = ["Turn on device 1.", "What state is device 2 in?", "Is device 3 on?",
             "Turn off device 4.", "Check device 5.", "Toggle device 6."]


def chat(messages, num_predict=40):
    body = json.dumps({"model": MODEL, "messages": messages, "stream": False,
                       "think": False, "keep_alive": -1,
                       "options": {"temperature": 0, "num_predict": num_predict}}).encode()
    req = urllib.request.Request(URL, body, {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as r:
        return json.load(r)


ms = lambda d, k: d[k] / 1e6
print(f"model {MODEL} at {URL}")
d = chat([{"role": "system", "content": SYSTEM}, {"role": "user", "content": "Hello."}])
print(f"cold   {ms(d, 'prompt_eval_duration'):8.1f} ms / {d['prompt_eval_count']} tok"
      f"   ({d['prompt_eval_count'] / (d['prompt_eval_duration'] / 1e9):.0f} tok/s prefill)")

fresh, follow = [], []
for q in QUESTIONS:
    msgs = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": q}]
    d = chat(msgs)
    fresh.append(ms(d, "prompt_eval_duration"))
    d2 = chat(msgs + [d["message"], {"role": "user", "content": "And the one after?"}])
    follow.append(ms(d2, "prompt_eval_duration"))

g = chat([{"role": "system", "content": SYSTEM},
          {"role": "user", "content": "Count from 1 to 60, comma separated."}], 200)
print(f"\nfresh conversation : {statistics.median(fresh):8.1f} ms")
print(f"follow-up turn     : {statistics.median(follow):8.1f} ms")
print(f"generation         : {g['eval_count'] / (g['eval_duration'] / 1e9):8.1f} tok/s"
      f"  ({g['eval_count']} tok)")
