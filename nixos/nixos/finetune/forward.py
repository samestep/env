"""Forward passes with a finished job's LoRA adapter, run inside the training
image by server.py. Reads /job/config.json and /job/data.jsonl, writes
/job/out/results.jsonl. The adapter is mounted read-only at /adapter.

Each "scale" multiplies the adapter's LoRA scaling: 0 is the untouched base
model, 1 the fine-tuned one.

mode "score": for each row {"id", "text", "prompt"?}, the log-probability of
  every token of "text" (conditioned on "prompt", if given) under each scale,
  plus optionally the top_k alternatives at each position.
mode "generate": for each row {"id", "prompt"}, n samples from a mixture of
  the scales' next-token log-probabilities, sum_i weights[i] * logp_i. With
  scales [1, 0] and weights [1 + a, -a] this is contrastive decoding
  (fine-tuned vs base); "plausibility" > 0 restricts sampling to tokens whose
  probability under the first scale is at least that fraction of its top
  token's.
"""

import json
import math

import torch
from peft import PeftModel
from peft.tuners.lora import LoraLayer
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig

with open("/job/config.json") as f:
    c = json.load(f)
with open("/job/data.jsonl") as f:
    rows = [json.loads(line) for line in f if line.strip()]

quant = {
    "4bit": BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type="nf4",
                               bnb_4bit_compute_dtype=torch.bfloat16),
    "8bit": BitsAndBytesConfig(load_in_8bit=True),
    "bf16": None,
}[c["precision"]]
tok = AutoTokenizer.from_pretrained(c["base_model"], trust_remote_code=False)
base = AutoModelForCausalLM.from_pretrained(
    c["base_model"], quantization_config=quant, torch_dtype=torch.bfloat16,
    device_map="cuda", attn_implementation="sdpa", trust_remote_code=False,
    use_safetensors=True,
)
model = PeftModel.from_pretrained(base, "/adapter").eval()
layers = [m for m in model.modules() if isinstance(m, LoraLayer)]
orig = [dict(m.scaling) for m in layers]


def set_scale(s):
    for m, o in zip(layers, orig):
        for k, v in o.items():
            m.scaling[k] = v * s


def encode(prompt, text):
    """Token ids and the index of the first token belonging to `text`."""
    p = tok(prompt, add_special_tokens=True)["input_ids"] if prompt else []
    t = tok(text, add_special_tokens=not p)["input_ids"] if text else []
    ids = (p + t)[: c["max_len"]]
    return ids, min(len(p), len(ids))


@torch.inference_mode()
def score(row):
    ids, start = encode(row.get("prompt", ""), row["text"])
    x = torch.tensor([ids], device="cuda")
    out = {"id": row.get("id"), "tokens": tok.convert_ids_to_tokens(ids[start:]),
           "logprobs": {}, "top": {} if c["top_k"] else None}
    for s in c["scales"]:
        set_scale(s)
        logits = model(x).logits[0, :-1]
        lp, top = [], []
        # Log-softmax in chunks to keep float32 logits small.
        for i in range(0, logits.shape[0], 1024):
            chunk = torch.log_softmax(logits[i : i + 1024].float(), -1)
            tgt = x[0, i + 1 : i + 1 + chunk.shape[0]]
            lp += chunk.gather(1, tgt[:, None])[:, 0].tolist()
            if c["top_k"]:
                v, k = chunk.topk(c["top_k"], -1)
                top += [[[tok.convert_ids_to_tokens(int(a)), round(float(b), 4)]
                         for a, b in zip(kk, vv)] for kk, vv in zip(k, v)]
        # Position j of lp predicts token j + 1; the first token of an
        # unprompted text has no context and gets None.
        keep = slice(start - 1, None) if start else slice(0, None)
        vals = [round(v, 4) for v in lp[keep]]
        out["logprobs"][str(s)] = vals if start else [None] + vals
        if c["top_k"]:
            t = top[keep]
            out["top"][str(s)] = t if start else [None] + t
    return out


@torch.inference_mode()
def generate(row):
    ids, _ = encode(row["prompt"], "")
    g = torch.Generator(device="cuda").manual_seed(c["seed"])
    samples = []
    for _ in range(c["n"]):
        caches = [None] * len(c["scales"])
        x = torch.tensor([ids], device="cuda")
        new = []
        for _ in range(c["max_new_tokens"]):
            mix = None
            for j, (s, w) in enumerate(zip(c["scales"], c["weights"])):
                set_scale(s)
                o = model(x, past_key_values=caches[j], use_cache=True)
                caches[j] = o.past_key_values
                lp = torch.log_softmax(o.logits[0, -1].float(), -1)
                if j == 0 and c["plausibility"] > 0:
                    mask = lp < lp.max() + math.log(c["plausibility"])
                mix = w * lp if mix is None else mix + w * lp
            if c["plausibility"] > 0:
                mix = mix.masked_fill(mask, float("-inf"))
            probs = torch.softmax(mix / c["temperature"], -1)
            if c["top_p"] < 1:
                sp, si = probs.sort(descending=True)
                cut = sp.cumsum(0) - sp > c["top_p"]
                sp[cut] = 0
                probs = torch.zeros_like(probs).scatter(0, si, sp)
            nxt = int(torch.multinomial(probs, 1, generator=g))
            if nxt == tok.eos_token_id:
                break
            new.append(nxt)
            x = torch.tensor([[nxt]], device="cuda")
        samples.append(tok.decode(new))
    return {"id": row.get("id"), "samples": samples}


with open("/job/out/results.jsonl", "w") as f:
    for i, row in enumerate(rows):
        f.write(json.dumps(score(row) if c["mode"] == "score" else generate(row)) + "\n")
        f.flush()
        print(f"row {i + 1}/{len(rows)}", flush=True)
