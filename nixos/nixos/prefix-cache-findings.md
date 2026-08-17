# Why fresh conversations re-prefill the whole system prompt

Status: **root cause found; fix 1 applied, measurement pending.**

Every Home Assistant command that starts a new conversation costs ~0.65 s of
prompt evaluation instead of ~0.19 s, because llama-server discards a cached
prefix it has already identified as reusable.

## The mechanism, from llama-server's own log

ollama runs llama-server with `--log-verbosity 4`, so this is in
`journalctl -u ollama`. One request, annotated:

    selected slot by LCP similarity, f_sim_best = 0.994 (1836/1848)
    new prompt, n_ctx_slot = 8192, n_keep = 4, task.n_tokens = 1848
    checking checkpoint with [1843, 1843] against 1836...
    checking checkpoint with [824, 824] against 1836...
    restored context checkpoint (pos_min = 824, n_tokens = 825, n_past = 825)
    cached n_tokens = 825, memory_seq_rm [825, end)
    prompt eval time = 667.37 ms / 1023 tokens

The slot selector finds **1836 of 1848 tokens** in common — it knows almost the
whole prompt is already cached. Then the context-checkpoint machinery takes
over. It cannot truncate the sequence at an arbitrary position; it can only roll
back to a checkpoint. The only checkpoints are at 824 and 1843. 1843 is past the
divergence point, so it falls back to 824 and re-prefills 1023 tokens.

Checkpoints are enabled because the context reports
`COMMON_CONTEXT_SEQ_RM_TYPE_FULL` ("can seq_rm full sequences only"), which
makes the server log "speculative decoding will use checkpoints". Partial
truncation degrades to checkpoint granularity, and checkpoints are sparse
because each one costs ~152 MiB.

## Candidate fixes, untested

Both are environment variables. ollama passes `cmd.Env = os.Environ()` to the
llama-server subprocess, so `services.ollama.environmentVariables` reaches it
with no patch.

1. `LLAMA_ARG_CTX_CHECKPOINTS=0` — disable checkpoints entirely. Should let the
   server truncate at 1836 and prefill ~12 tokens. Risk: checkpoints exist to
   support speculative decoding on a FULL-only context, so this may disable or
   degrade MTP, which is worth ~1.7x on generation. Measure both prefill and
   tokens/sec before keeping it.
2. `LLAMA_ARG_CHECKPOINT_MIN_SPACING_NT=<small>` — keep checkpoints but space
   them closely, so a rollback loses less. Costs VRAM: ~152 MiB each, up to 32.

Both bindings verified present in `common/arg.cpp` at llama.cpp b10380, which is
what ollama 0.32.13 vendors.

## Ruled out — do not retry these

Each was tested, not reasoned about:

- **Slot count.** ollama passes `-np 1`; there is one slot. Adding a second does
  not help: slot choice is LCP-based here, not LRU.
- **`prompt_clear()` on a level-2 cache miss.** `LLAMA_ARG_CACHE_RAM=0` skips
  that block entirely (the cache is only constructed when `cache_ram_mib != 0`,
  and `update_cache && prompt_cache` then short-circuits). Measured: no change.
- **`--slot-prompt-similarity`.** Already effectively enabled — the log shows
  `selected slot by LCP similarity`. Selection was never the problem.
- **MTP / the draft head.** The non-MTP `qwen3.6:27b-q4_K_M` is equally slow.
- **`--mmproj` / vision.** A projector-stripped variant built with
  `/api/create` (capabilities lost `vision`, kept `tools` and `thinking`) is
  equally slow.
- **`--flash-attn on`, `--context-shift --keep 4`, `--no-jinja --chat-template
  chatml`, `-b/-ub 1024`.** Each added individually to a stock llama-server:
  prefix reuse still works.
- **Renderer-injected timestamps.** ollama's qwen renderers contain no
  time-varying content. (`glimmer.go` does inject `Current date:`, so this would
  be a real issue for Muse Glimmer.)

Also false, from earlier commit messages: llama-server does **not** require the
new prompt to extend the cached one. It computes
`n_past = slot.prompt.tokens.get_common_prefix(input_tokens)` — a genuine
longest common prefix. Verified standalone: three fresh conversations sharing
only a system prefix prefilled 9, 10 and 10 tokens.

## Measurement traps that produced false results here

- **A synthetic system prompt is not Home Assistant's.** If HA sends anything
  during a benchmark, it replaces the slot contents and the next synthetic
  request shares nothing with it. Quiesce HA, or use HA's own prompt.
- **`prompt_eval_count` always reports the full prompt**, even when almost all
  of it was reused. Only `prompt_eval_duration` is a signal.
- **Back-to-back requests are not representative.** With the priming proxy in
  place, requests fired with no gap contend with the replay: 3.47 s at 0 s
  spacing, 2.52 s at 2 s, 1.79 s at 5 s. Voice usage looks like the last one.
- **There is ~0.15 s of fixed per-request overhead**, so a perfect cache hit
  reads as ~0.19 s, not ~0.02 s.
- Compare like with like: a prompt without `tools` is ~780 tokens against ~1850
  with them.

## Baselines to compare a fix against

Measured through the primer on `qwen3.6:27b-mtp-q8_0`, which does not affect
generation:

- **Generation: 77 tok/s median** (with MTP). This is the number fix 1 puts at
  risk. If it drops toward ~45 tok/s, checkpoints were load-bearing for
  speculative decoding and fix 2 is the one to take.
- **Prefill: ~152 ms for a 25-token prompt**, i.e. the fixed per-request
  overhead. A perfect cache hit cannot read below roughly this.

## What the priming proxy was for

`ollama-primer.py` replayed each request with the conversation stripped, leaving
the slot holding just the prefix, so the next request was a strict extension and
needed no truncation at all. It worked — 0.19 s — and sidestepped the checkpoint
problem rather than fixing it.

It is now **deleted**, along with the port shuffle: ollama is back on 11434,
bound to 0.0.0.0 so the agent VM can measure it directly. Note that this
deletion was a precondition for measuring fix 1 honestly, not just cleanup — a
running primer holds the slot in exactly the state the fix is meant to produce,
so any measurement taken with it in the path is unfalsifiable (trap 1).

If fix 1 has to be reverted, the proxy is recoverable from git history rather
than worth rewriting.
