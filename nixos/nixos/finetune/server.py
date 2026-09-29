"""A small job runner for fine-tuning local models on this machine's GPU.

Guests on the libvirt bridge submit a dataset, a Hugging Face base model and a
handful of whitelisted hyperparameters; this server turns them into a training config, runs pinned
containers (train, merge, convert to GGUF, quantize) one job at a time, and
serves back the logs and the resulting files. It never runs anything supplied
by a client: every command line is fixed here, and client values only ever
reach a generated JSON config after type and range checks.

API (all JSON unless noted):
  GET    /serve                  the llama-server currently up, if any
  POST   /serve                  serve {"job": id, "file": "<.gguf>", "ctx": n, "parallel": n}
                                 (OpenAI-compatible API on FINETUNE_SERVE_PORT)
  DELETE /serve                  stop it
  GET    /jobs                   list jobs
  POST   /jobs                   submit {"config": {...}, "data": "<jsonl>"}
  POST   /jobs/<id>/forward      queue a scoring or generation run with finished
                                 training job <id>'s adapter, {"config": {...},
                                 "data": "<jsonl>"}; see ./forward.py. Results
                                 are the new job's out/results.jsonl
  GET    /jobs/<id>              one job's status
  GET    /jobs/<id>/log?tail=N   plain-text log (last N lines)
  GET    /jobs/<id>/files        list output files
  GET    /jobs/<id>/files/<name> download one output file
  DELETE /jobs/<id>              cancel (queued or running)
"""

import json
import os
import re
import secrets
import shutil
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATE = os.environ.get("FINETUNE_STATE", "/var/lib/finetune")
LISTEN = os.environ.get("FINETUNE_LISTEN", "0.0.0.0")
PORT = int(os.environ.get("FINETUNE_PORT", "11500"))
# llama-server for a finished job's GGUF, published only on this address.
SERVE_BIND = os.environ.get("FINETUNE_SERVE_BIND", "192.168.122.1")
SERVE_PORT = int(os.environ.get("FINETUNE_SERVE_PORT", "11501"))
SERVE_NAME = "finetune-serve"
# Any public Hugging Face repo with safetensors weights up to this size. Code
# shipped in a repo is never run (trust_remote_code stays off), and pickled
# weights are never loaded.
MAX_MODEL_BYTES = int(os.environ.get("FINETUNE_MAX_MODEL_BYTES", str(150 * 2**30)))
HF_API = "https://huggingface.co/api/models/"
TRAIN_IMAGE = os.environ["FINETUNE_TRAIN_IMAGE"]
CONVERT_IMAGE = os.environ["FINETUNE_CONVERT_IMAGE"]
FORWARD_SCRIPT = os.environ["FINETUNE_FORWARD_SCRIPT"]
OLLAMA = os.environ.get("FINETUNE_OLLAMA_URL", "")  # unload models before training
DOCKER = os.environ.get("FINETUNE_DOCKER", "docker")
MAX_DATA_BYTES = int(os.environ.get("FINETUNE_MAX_DATA_BYTES", str(512 * 2**20)))

JOBS = os.path.join(STATE, "jobs")
HF_CACHE = os.path.join(STATE, "hf")
os.makedirs(JOBS, exist_ok=True)
os.makedirs(HF_CACHE, exist_ok=True)

# name: (type, min, max) for numbers, or a tuple of allowed strings.
PARAMS = {
    "base_model": None,  # checked by check_model
    # sft trains on "dataset_type" rows; the preference objectives take
    # {"prompt", "chosen", "rejected"} rows (dpo, ipo, simpo) or
    # {"prompt", "completion", "label": bool} rows (kto).
    "objective": ("sft", "dpo", "ipo", "simpo", "kto"),
    "rl_beta": (float, 0.001, 10.0),
    "simpo_gamma": (float, 0.0, 10.0),
    "dataset_type": ("completion", "input_output", "chat_template"),
    "adapter": ("qlora", "lora"),
    "lora_r": (int, 4, 256),
    "lora_alpha": (int, 4, 512),
    "lora_dropout": (float, 0.0, 0.5),
    "learning_rate": (float, 1e-6, 1e-3),
    "num_epochs": (float, 0.1, 10),
    "sequence_len": (int, 256, 32768),
    "micro_batch_size": (int, 1, 64),
    "gradient_accumulation_steps": (int, 1, 256),
    "val_set_size": (float, 0.0, 0.5),
    "warmup_ratio": (float, 0.0, 0.5),
    "seed": (int, 0, 2**31 - 1),
    "quantize": ("none", "Q8_0", "Q6_K", "Q5_K_M", "Q4_K_M"),
    "merge": (True, False),
}
DEFAULTS = {
    "objective": "sft",
    "rl_beta": 0.1,
    "simpo_gamma": 0.5,
    "dataset_type": "input_output",
    "adapter": "qlora",
    "lora_r": 32,
    "lora_alpha": 64,
    "lora_dropout": 0.05,
    "learning_rate": 1e-4,
    "num_epochs": 2,
    "sequence_len": 4096,
    "micro_batch_size": 1,
    "gradient_accumulation_steps": 8,
    "val_set_size": 0.05,
    "warmup_ratio": 0.03,
    "seed": 42,
    "quantize": "Q8_0",
    "merge": True,
}

# Forward runs: same rule format, plus the lists checked in validate_forward.
FORWARD_PARAMS = {
    "mode": ("score", "generate"),
    "precision": ("4bit", "8bit", "bf16"),
    "max_len": (int, 16, 32768),
    "top_k": (int, 0, 20),
    "max_new_tokens": (int, 1, 4096),
    "n": (int, 1, 16),
    "temperature": (float, 0.01, 5.0),
    "top_p": (float, 0.01, 1.0),
    "plausibility": (float, 0.0, 1.0),
    "seed": (int, 0, 2**31 - 1),
    "scales": None,
    "weights": None,
    "stop": None,
}
FORWARD_DEFAULTS = {
    "mode": "score",
    "precision": "4bit",
    "max_len": 4096,
    "top_k": 0,
    "max_new_tokens": 512,
    "n": 1,
    "temperature": 0.8,
    "top_p": 1.0,
    "plausibility": 0.0,
    "seed": 42,
    "scales": [0.0, 1.0],
}

lock = threading.Lock()
queue = []  # job ids, oldest first
running = {"id": None, "container": None}
serving = {}  # the llama-server currently up, if any


def job_dir(jid):
    if not re.fullmatch(r"[0-9a-f]{12}", jid or ""):
        raise KeyError(jid)
    d = os.path.join(JOBS, jid)
    if not os.path.isdir(d):
        raise KeyError(jid)
    return d


def read_status(jid):
    with open(os.path.join(job_dir(jid), "status.json")) as f:
        return json.load(f)


def write_status(jid, **kw):
    path = os.path.join(JOBS, jid, "status.json")
    st = {}
    if os.path.exists(path):
        with open(path) as f:
            st = json.load(f)
    st.update(kw, updated=time.time())
    with open(path + ".tmp", "w") as f:
        json.dump(st, f, indent=1)
    os.replace(path + ".tmp", path)


def validate(cfg, params=PARAMS, defaults=DEFAULTS):
    if not isinstance(cfg, dict):
        raise ValueError("config must be an object")
    unknown = set(cfg) - set(params)
    if unknown:
        raise ValueError(f"unknown config keys: {sorted(unknown)}")
    out = dict(defaults)
    for k, v in cfg.items():
        rule = params[k]
        if rule is None:
            out[k] = v
            continue
        if rule and isinstance(rule[0], type):
            t, lo, hi = rule
            if isinstance(v, bool) or not isinstance(v, (int, float)):
                raise ValueError(f"{k} must be a number")
            if t is int and v != int(v):
                raise ValueError(f"{k} must be an integer")
            v = t(v)
            if not lo <= v <= hi:
                raise ValueError(f"{k} must be in [{lo}, {hi}]")
        elif v not in rule:
            raise ValueError(f"{k} must be one of {list(rule)}")
        out[k] = v
    if params is PARAMS:
        out["base_model"] = check_model(out.get("base_model"))
    return out


model_ok = {}  # repo -> True once checked


def check_model(name):
    if not isinstance(name, str) or not re.fullmatch(r"[\w][\w.-]*/[\w][\w.-]*", name) \
            or ".." in name:
        raise ValueError("base_model must be a Hugging Face repo id like owner/name")
    if name in model_ok:
        return name
    try:
        with urllib.request.urlopen(HF_API + name + "?blobs=true", timeout=30) as r:
            info = json.load(r)
    except Exception as e:
        raise ValueError(f"can't look up {name} on Hugging Face (missing, gated or private?): {e}")
    if info.get("gated") or info.get("private") or info.get("disabled"):
        raise ValueError(f"{name} is gated or private")
    files = info.get("siblings", [])
    weights = [f for f in files if f["rfilename"].endswith(".safetensors")]
    if not weights:
        raise ValueError(f"{name} has no safetensors weights")
    size = sum(f.get("size") or 0 for f in weights)
    if size > MAX_MODEL_BYTES:
        raise ValueError(f"{name} weights are {size / 2**30:.0f} GiB; the limit is "
                         f"{MAX_MODEL_BYTES / 2**30:.0f} GiB")
    if (info.get("config") or {}).get("auto_map"):
        raise ValueError(f"{name} needs custom code, which is never run here")
    model_ok[name] = True
    return name


def number_list(v, name, lo, hi):
    if not (isinstance(v, list) and 1 <= len(v) <= 4) or any(
        isinstance(x, bool) or not isinstance(x, (int, float)) or not lo <= x <= hi for x in v
    ):
        raise ValueError(f"{name} must be a list of 1-4 numbers in [{lo}, {hi}]")
    return [float(x) for x in v]


def validate_forward(cfg, src):
    """A forward run's config; the base model comes from source job `src`."""
    st = read_status(src)
    adapter = os.path.join(job_dir(src), "out", "adapter", "adapter_config.json")
    if st.get("config", {}).get("kind") == "forward" or st.get("state") != "done" \
            or not os.path.exists(adapter):
        raise ValueError("source must be a finished training job with an adapter")
    out = validate(cfg, FORWARD_PARAMS, FORWARD_DEFAULTS)
    out["scales"] = number_list(out["scales"], "scales", 0.0, 2.0)
    out["weights"] = number_list(
        out.get("weights", [1.0] + [0.0] * (len(out["scales"]) - 1)), "weights", -8.0, 8.0)
    if len(out["weights"]) != len(out["scales"]):
        raise ValueError("weights must be as long as scales")
    out["stop"] = out.get("stop", [])
    if not (isinstance(out["stop"], list) and len(out["stop"]) <= 4
            and all(isinstance(x, str) and 0 < len(x) <= 32 for x in out["stop"])):
        raise ValueError("stop must be a list of up to 4 strings of 1-32 characters")
    return dict(out, kind="forward", source=src, base_model=st["config"]["base_model"])


def validate_forward_data(text, mode):
    if len(text.encode()) > MAX_DATA_BYTES:
        raise ValueError("data too large")
    n = 0
    for i, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        row = json.loads(line)
        need = ("text",) if mode == "score" else ("prompt",)
        if not isinstance(row, dict) or any(not isinstance(row.get(k), str) for k in need) \
                or not isinstance(row.get("prompt", ""), str):
            raise ValueError(f"line {i}: {mode} rows need string {' and '.join(need)}")
        n += 1
    if n == 0:
        raise ValueError("no rows")
    return n


def validate_data(text, dataset_type, objective="sft"):
    if len(text.encode()) > MAX_DATA_BYTES:
        raise ValueError("data too large")
    n = 0
    for i, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        row = json.loads(line)
        if not isinstance(row, dict):
            raise ValueError(f"line {i}: rows must be objects")
        if objective in ("dpo", "ipo", "simpo"):
            if any(not isinstance(row.get(k), str) for k in ("prompt", "chosen", "rejected")):
                raise ValueError(f"line {i}: {objective} rows need string prompt, chosen, rejected")
        elif objective == "kto":
            if any(not isinstance(row.get(k), str) for k in ("prompt", "completion")) \
                    or not isinstance(row.get("label"), bool):
                raise ValueError(f"line {i}: kto rows need string prompt, completion and bool label")
        elif dataset_type == "completion" and not isinstance(row.get("text"), str):
            raise ValueError(f"line {i}: completion rows need a string 'text'")
        elif dataset_type == "input_output" and not isinstance(row.get("segments"), list):
            raise ValueError(f"line {i}: input_output rows need a 'segments' list")
        elif dataset_type == "chat_template" and not isinstance(row.get("messages"), list):
            raise ValueError(f"line {i}: chat_template rows need a 'messages' list")
        n += 1
    if n == 0:
        raise ValueError("no rows")
    return n


def train_config(c):
    """Axolotl config. JSON is valid YAML, so we write JSON."""
    ds = {"path": "/job/data.jsonl", "type": c["dataset_type"]}
    if c["dataset_type"] == "chat_template":
        ds["field_messages"] = "messages"
    rl = {}
    if c["objective"] != "sft":
        # Plain-text user_defined formats, so base models need no chat template.
        if c["objective"] == "kto":
            ds = {"path": "/job/data.jsonl", "split": "train", "type": {
                "field_prompt": "prompt", "field_completion": "completion", "field_label": "label",
                "prompt_format": "{prompt}", "completion_format": "{completion}"}}
        else:
            ds = {"path": "/job/data.jsonl", "split": "train", "type": {
                "field_prompt": "prompt", "field_chosen": "chosen", "field_rejected": "rejected",
                "prompt_format": "{prompt}", "chosen_format": "{chosen}",
                "rejected_format": "{rejected}"}}
        rl = {"rl": "dpo" if c["objective"] == "ipo" else c["objective"],
              "rl_beta": c["rl_beta"], "remove_unused_columns": False}
        if c["objective"] == "ipo":
            rl["dpo_loss_type"] = ["ipo"]
        if c["objective"] == "simpo":
            rl["simpo_gamma"] = c["simpo_gamma"]
    return rl | {
        "trust_remote_code": False,
        "base_model": c["base_model"],
        "load_in_4bit": c["adapter"] == "qlora",
        "adapter": c["adapter"],
        "lora_r": c["lora_r"],
        "lora_alpha": c["lora_alpha"],
        "lora_dropout": c["lora_dropout"],
        "lora_target_linear": True,
        "datasets": [ds],
        "dataset_prepared_path": "/job/prepared",
        "val_set_size": c["val_set_size"],
        "output_dir": "/job/out/adapter",
        "sequence_len": c["sequence_len"],
        "sample_packing": c["dataset_type"] == "completion" and not rl,
        "pad_to_sequence_len": c["dataset_type"] == "completion" and not rl,
        "micro_batch_size": c["micro_batch_size"],
        "gradient_accumulation_steps": c["gradient_accumulation_steps"],
        "num_epochs": c["num_epochs"],
        "learning_rate": c["learning_rate"],
        "lr_scheduler": "cosine",
        "warmup_ratio": c["warmup_ratio"],
        "optimizer": "adamw_torch_fused" if c["adapter"] == "lora" else "paged_adamw_8bit",
        "bf16": True,
        "tf32": True,
        "gradient_checkpointing": True,
        "flash_attention": True,
        # The flash-attn kernel rejects attention dropout, which some model
        # configs (e.g. Seed-OSS) enable by default.
        "overrides_of_model_config": {"attention_dropout": 0.0},
        "logging_steps": 5,
        "evals_per_epoch": 4 if c["val_set_size"] > 0 else 0,
        "saves_per_epoch": 1,
        "save_total_limit": 2,
        "seed": c["seed"],
    }


def stop_server():
    subprocess.run([DOCKER, "rm", "-f", SERVE_NAME], capture_output=True)
    with lock:
        serving.clear()


def start_server(jid, name, ctx, parallel):
    if name not in {f["name"] for f in output_files(jid)} or not name.endswith(".gguf"):
        raise ValueError("file must be one of this job's .gguf outputs")
    stop_server()
    cmd = [
        DOCKER, "run", "-d", "--name", SERVE_NAME,
        "--device", "nvidia.com/gpu=all",
        "-p", f"{SERVE_BIND}:{SERVE_PORT}:8080",
        "-v", f"{os.path.join(JOBS, jid, 'out')}:/models:ro",
        "--entrypoint", "/app/llama-server", CONVERT_IMAGE,
        "--host", "0.0.0.0", "--port", "8080", "-m", f"/models/{name}",
        "-ngl", "999", "-c", str(ctx), "-np", str(parallel), "--flash-attn", "on",
    ]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip()[-500:])
    with lock:
        serving.update(job=jid, file=name, ctx=ctx, parallel=parallel,
                       url=f"http://{SERVE_BIND}:{SERVE_PORT}", started=time.time())


def unload_ollama(log):
    if not OLLAMA:
        return
    try:
        with urllib.request.urlopen(OLLAMA + "/api/ps", timeout=10) as r:
            models = [m["name"] for m in json.load(r).get("models", [])]
        for m in models:
            req = urllib.request.Request(
                OLLAMA + "/api/generate",
                data=json.dumps({"model": m, "keep_alive": 0}).encode(),
                headers={"Content-Type": "application/json"},
            )
            urllib.request.urlopen(req, timeout=60).read()
            log.write(f"unloaded ollama model {m}\n")
    except Exception as e:  # ollama may simply not be running
        log.write(f"ollama unload skipped: {e}\n")


def run_step(jid, name, image, args, log, mounts=()):
    container = f"finetune-{jid}-{name}"
    cmd = [
        DOCKER, "run", "--rm", "--name", container,
        "--device", "nvidia.com/gpu=all", "--shm-size=16g",
        *[a for m in mounts for a in ("-v", m)],
        "-v", f"{os.path.join(JOBS, jid)}:/job",
        "-v", f"{HF_CACHE}:/hf", "-e", "HF_HOME=/hf",
        "--entrypoint", args[0], image, *args[1:],
    ]
    log.write(f"\n=== {name}: {' '.join(cmd)}\n")
    log.flush()
    with lock:
        running["container"] = container
    rc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT).returncode
    with lock:
        running["container"] = None
    if rc != 0:
        raise RuntimeError(f"{name} failed with exit code {rc}")


def run_job(jid):
    d = os.path.join(JOBS, jid)
    with open(os.path.join(d, "config.json")) as f:
        c = json.load(f)
    os.makedirs(os.path.join(d, "out"), exist_ok=True)
    if c.get("kind") != "forward":
        with open(os.path.join(d, "train.yml"), "w") as f:
            json.dump(train_config(c), f, indent=1)
    with open(os.path.join(d, "log.txt"), "a") as log:
        unload_ollama(log)
        if serving:
            log.write(f"stopping llama-server for job {serving.get('job')}\n")
            stop_server()
        if c.get("kind") == "forward":
            write_status(jid, state="running", step="forward", started=time.time())
            adapter = os.path.join(JOBS, c["source"], "out", "adapter")
            run_step(jid, "forward", TRAIN_IMAGE, ["python3", "/runner/forward.py"], log,
                     mounts=[f"{adapter}:/adapter:ro", f"{FORWARD_SCRIPT}:/runner/forward.py:ro"])
            return
        write_status(jid, state="running", step="train", started=time.time())
        run_step(jid, "train", TRAIN_IMAGE, ["axolotl", "train", "/job/train.yml"], log)
        if not c["merge"]:
            return
        write_status(jid, step="merge")
        run_step(jid, "merge", TRAIN_IMAGE,
                 ["axolotl", "merge-lora", "/job/train.yml", "--lora-model-dir=/job/out/adapter"], log)
        write_status(jid, step="convert")
        run_step(jid, "convert", CONVERT_IMAGE,
                 ["python3", "/app/convert_hf_to_gguf.py", "/job/out/adapter/merged",
                  "--outtype", "bf16", "--outfile", "/job/out/model-bf16.gguf"], log)
        if c["quantize"] != "none":
            write_status(jid, step="quantize")
            q = c["quantize"]
            run_step(jid, "quantize", CONVERT_IMAGE,
                     ["/app/llama-quantize", "/job/out/model-bf16.gguf", f"/job/out/model-{q}.gguf", q], log)
            run_step(jid, "rm-bf16", CONVERT_IMAGE, ["rm", "-f", "/job/out/model-bf16.gguf"], log)
        # The merged weights (tens of GB) are only an intermediate. Containers
        # run as root, so their files are root-owned: delete them from one.
        write_status(jid, step="cleanup")
        run_step(jid, "cleanup", CONVERT_IMAGE, ["rm", "-rf", "/job/out/adapter/merged"], log)


def worker():
    while True:
        with lock:
            jid = queue.pop(0) if queue else None
            running["id"] = jid
        if jid is None:
            time.sleep(2)
            continue
        try:
            if read_status(jid).get("state") == "cancelled":
                continue
            run_job(jid)
            if read_status(jid).get("state") != "cancelled":
                write_status(jid, state="done", step=None, finished=time.time())
        except Exception as e:
            if read_status(jid).get("state") != "cancelled":
                write_status(jid, state="failed", error=str(e), finished=time.time())
        finally:
            with lock:
                running["id"] = None


def output_files(jid):
    out = os.path.join(job_dir(jid), "out")
    files = []
    for root, _, names in os.walk(out):
        for n in names:
            p = os.path.join(root, n)
            files.append({"name": os.path.relpath(p, out), "bytes": os.path.getsize(p)})
    return sorted(files, key=lambda f: f["name"])


class Handler(BaseHTTPRequestHandler):
    def send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else (
            body if ctype != "application/json" else json.dumps(body, indent=1)
        ).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def parts(self):
        path, _, query = self.path.partition("?")
        return [p for p in path.split("/") if p], dict(
            kv.split("=", 1) for kv in query.split("&") if "=" in kv
        )

    def do_GET(self):
        p, q = self.parts()
        try:
            if p == ["serve"]:
                up = subprocess.run([DOCKER, "ps", "-q", "--filter", f"name=^{SERVE_NAME}$"],
                                    capture_output=True, text=True).stdout.strip()
                return self.send(200, dict(serving, running=bool(up)))
            if p == ["jobs"]:
                ids = sorted(os.listdir(JOBS), key=lambda j: os.path.getmtime(os.path.join(JOBS, j)))
                return self.send(200, [dict(read_status(j), id=j) for j in ids])
            if len(p) == 2 and p[0] == "jobs":
                return self.send(200, dict(read_status(p[1]), id=p[1], queue=list(queue)))
            if len(p) == 3 and p[0] == "jobs" and p[2] == "log":
                with open(os.path.join(job_dir(p[1]), "log.txt"), errors="replace") as f:
                    lines = f.read().splitlines()
                n = int(q.get("tail", "200"))
                return self.send(200, "\n".join(lines[-n:]) + "\n", "text/plain; charset=utf-8")
            if len(p) == 3 and p[0] == "jobs" and p[2] == "files":
                return self.send(200, output_files(p[1]))
            if len(p) >= 4 and p[0] == "jobs" and p[2] == "files":
                name = "/".join(p[3:])
                if name not in {f["name"] for f in output_files(p[1])}:
                    raise KeyError(name)
                path = os.path.join(job_dir(p[1]), "out", name)
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(os.path.getsize(path)))
                self.end_headers()
                with open(path, "rb") as f:
                    shutil.copyfileobj(f, self.wfile)
                return
            self.send(404, {"error": "not found"})
        except (KeyError, FileNotFoundError):
            self.send(404, {"error": "not found"})

    def do_POST(self):
        p, _ = self.parts()
        if p == ["serve"]:
            try:
                length = int(self.headers.get("Content-Length", "0"))
                body = json.loads(self.rfile.read(length)) if 0 < length < 2**16 else {}
                jid, name = body["job"], body["file"]
                ctx = int(body.get("ctx", 8192)); par = int(body.get("parallel", 1))
                if not (512 <= ctx <= 131072 and 1 <= par <= 16):
                    raise ValueError("ctx must be in [512, 131072], parallel in [1, 16]")
                if running["id"] is not None:
                    raise ValueError("a training job is running")
                job_dir(jid)
                start_server(jid, name, ctx, par)
                return self.send(200, dict(serving))
            except KeyError:
                return self.send(404, {"error": "job or file not found"})
            except (ValueError, TypeError, json.JSONDecodeError, RuntimeError) as e:
                return self.send(400, {"error": str(e)})
        forward = len(p) == 3 and p[0] == "jobs" and p[2] == "forward"
        if p != ["jobs"] and not forward:
            return self.send(404, {"error": "not found"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = -1
        if length < 0:
            return self.send(400, {"error": "bad Content-Length"})
        if length > MAX_DATA_BYTES + 2**20:
            return self.send(413, {"error": "too large"})
        try:
            body = json.loads(self.rfile.read(length))
            if forward:
                cfg = validate_forward(body.get("config", {}), p[1])
                rows = validate_forward_data(body.get("data", ""), cfg["mode"])
            else:
                cfg = validate(body.get("config", {}))
                rows = validate_data(body.get("data", ""), cfg["dataset_type"], cfg["objective"])
        except KeyError:
            return self.send(404, {"error": "source job not found"})
        except (ValueError, TypeError, json.JSONDecodeError, AttributeError) as e:
            return self.send(400, {"error": str(e)})
        jid = secrets.token_hex(6)
        d = os.path.join(JOBS, jid)
        os.makedirs(d)
        with open(os.path.join(d, "data.jsonl"), "w") as f:
            f.write(body["data"])
        with open(os.path.join(d, "config.json"), "w") as f:
            json.dump(cfg, f, indent=1)
        open(os.path.join(d, "log.txt"), "w").close()
        write_status(jid, state="queued", rows=rows, config=cfg, submitted=time.time())
        with lock:
            queue.append(jid)
        self.send(201, {"id": jid})

    def do_DELETE(self):
        p, _ = self.parts()
        if p == ["serve"]:
            stop_server()
            return self.send(200, {"serving": False})
        try:
            if len(p) != 2 or p[0] != "jobs":
                raise KeyError()
            jid = p[1]
            job_dir(jid)
            write_status(jid, state="cancelled", finished=time.time())
            with lock:
                if jid in queue:
                    queue.remove(jid)
                container = running["container"] if running["id"] == jid else None
            if container:
                subprocess.run([DOCKER, "kill", container], capture_output=True)
            self.send(200, {"id": jid, "state": "cancelled"})
        except KeyError:
            self.send(404, {"error": "not found"})


def kill_leftover_containers():
    """`docker run` clients die with the service, but their containers keep
    running under dockerd; stop any we started so they don't hold the GPU."""
    ids = subprocess.run(
        [DOCKER, "ps", "-q", "--filter", "name=^finetune-"],
        capture_output=True, text=True,
    ).stdout.split()
    if ids:
        subprocess.run([DOCKER, "kill", *ids], capture_output=True)


def recover():
    """Requeue jobs that were queued or interrupted when the service stopped."""
    kill_leftover_containers()
    for jid in sorted(os.listdir(JOBS), key=lambda j: os.path.getmtime(os.path.join(JOBS, j))):
        try:
            st = read_status(jid)
        except (KeyError, FileNotFoundError, json.JSONDecodeError):
            continue
        if st.get("state") == "running":
            write_status(jid, state="failed", error="interrupted by service restart")
        elif st.get("state") == "queued":
            queue.append(jid)


if __name__ == "__main__":
    recover()
    threading.Thread(target=worker, daemon=True).start()
    ThreadingHTTPServer((LISTEN, PORT), Handler).serve_forever()
