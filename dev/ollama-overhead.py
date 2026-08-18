"""How much of an ollama request happens before any inference does.

ollama reports load_duration for every request. On a model that is already
resident that should be nothing, and it is not: answering "what is this model
capable of" means reading and parsing the GGUF metadata, and the chat path asks
twice per request. Generating a single token makes the rest of the request small
enough that the overhead is the whole measurement.

    dev/py dev/ollama-overhead.py <url> <model> [<url> <model>...]
"""
import json, statistics, sys, time, urllib.request


def measure(url, model, n=7):
    walls, loads, prompts = [], [], []
    for i in range(n):
        body = {"model": model, "stream": False, "keep_alive": "-1s",
                "think": False, "options": {"num_predict": 1},
                "messages": [{"role": "user", "content": "hi"}]}
        req = urllib.request.Request(f"{url}/api/chat",
                                     data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        t0 = time.monotonic()
        d = json.load(urllib.request.urlopen(req, timeout=600))
        if i:  # the first may still be loading the model
            walls.append((time.monotonic() - t0) * 1000)
            loads.append(d.get("load_duration", 0) / 1e6)
            prompts.append(d.get("prompt_eval_duration", 0) / 1e6)
    m = statistics.median
    return m(walls), m(loads), m(prompts)


args = sys.argv[1:]
if len(args) < 2 or len(args) % 2:
    print(__doc__)
    raise SystemExit(1)

print(f"{'target':44} {'wall':>8} {'before inference':>17} {'prompt':>8}")
for url, model in zip(args[::2], args[1::2]):
    wall, load, prompt = measure(url, model)
    print(f"  {url + '  ' + model:42} {wall:8.1f} {load:17.1f} {prompt:8.1f}")
