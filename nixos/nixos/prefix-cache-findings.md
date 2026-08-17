Status: **fixed.** Fresh-conversation prefill 1770 ms -> 437 ms, against a
185 ms floor. One unexplained 250 ms remains; see the last section.

Every Home Assistant command that starts a new conversation costs ~0.65 s of
prompt evaluation instead of ~0.19 s, because llama-server discards a cached
prefix it has already identified as reusable.

## Why this model can only reuse a prefix via checkpoints

`general.architecture` is `qwen35`, and `qwen35.full_attention_interval = 4`:
only every 4th layer is full attention. The other three quarters are linear
layers carrying a **recurrent state**, not a KV cache.

A recurrent state has no per-position structure to truncate. You can advance it,
snapshot it, or reset it — nothing else. So the context reports
`COMMON_CONTEXT_SEQ_RM_TYPE_FULL` ("can seq_rm full sequences only"), and
**context checkpoints are the only prefix-reuse mechanism that exists here.**
They are not an optimization layered on top of ordinary reuse; they are it.

This is the fact that made the earlier rounds of this investigation
unintelligible, and it is worth holding onto: `/api/show` reports it in one
call, and it explains the behaviour that looked like a caching bug.

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

The slot selector finds **1836 of 1848 tokens** in common. The server then has
to land on a checkpoint at or before 1836. The only ones are 824 and 1843; 1843
is past the divergence point, so it falls back to 824 and re-prefills 1023
tokens.

## The fix: stop suppressing the checkpoint we want

Checkpoints are **not** placed on a grid. The server parses the rendered chat
into role spans and snapshots at the start of each user message
(`spans.is_user_start`, `common/chat.h:174`), plus once near the end of the
prompt. Those are already the positions worth saving: the boundary just after
system+tools, and the end of the conversation so far.

`checkpoint_min_step` is a throttle on that placement, not the placement itself
— take this user-boundary checkpoint only if it is at least min_step past the
last one. It defaults to **8192 tokens** while our whole prompt is 1848, so it
suppressed the checkpoint at the end of the system prefix, which is exactly
where every new conversation diverges.

Applied: `LLAMA_ARG_CHECKPOINT_MIN_SPACING_NT=128`. Worst-case rollback becomes
128 tokens (~70 ms at the measured ~1800 tok/s prefill rate), and the default 32
checkpoints then cover 4096 tokens of history.

Checkpoints are `std::vector<uint8_t>` in `common_prompt_checkpoint`, i.e. **host
RAM, not VRAM** — ~152 MiB each, ~4.8 GB at the default count, against 128 GiB.
An earlier version of this document said VRAM; that was wrong, and it made the
budget look tight when it is free.

## Tried and rejected: `LLAMA_ARG_CTX_CHECKPOINTS=0`

This was the first candidate, on the theory that removing checkpoints would
leave plain longest-common-prefix reuse. It does the opposite. With no
checkpoints the restore path finds nothing to land on, sets `do_reset`, and
re-prefills from zero — **every request, including a byte-exact append**:

    turn 0: 3117.4 ms / 5784 tok
    turn 4: 3282.5 ms / 5872 tok

against a ~150 ms floor. Generation read 91 tok/s here, but that is not evidence
that checkpoints cost generation: with the fix applied it reads 92.8 tok/s. The
77 tok/s baseline was taken on a ~28-token prompt and does not compare.

The useful by-product: this proved the env-var channel works. ollama passes
`cmd.Env = os.Environ()` to llama-server, so `services.ollama.environmentVariables`
reaches `LLAMA_ARG_*` with no patch. That had been assumed, never demonstrated.

## Ruled out — do not retry these

Each was tested, not reasoned about:

- **Slot count.** ollama passes `-np 1`; there is one slot. Adding a second does
  not help: slot choice is LCP-based here, not LRU.
- **`prompt_clear()` on a level-2 cache miss.** `LLAMA_ARG_CACHE_RAM=0` skips
  that block entirely (the cache is only constructed when `cache_ram_mib != 0`,
  and `update_cache && prompt_cache` then short-circuits). Measured: no change.
- **`--slot-prompt-similarity`.** Already effectively enabled — the log shows
  `selected slot by LCP similarity`. Selection was never the problem.
- **`--swa-full` / `LLAMA_ARG_SWA_FULL`.** Irrelevant: this model has no sliding
  window. `--ctx-checkpoints` carries `--swa-checkpoints` as an alias, which
  makes checkpoints look like an SWA feature; they serve recurrent state too.
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

Note that standalone test used an ordinary transformer, where the common prefix
is the whole story. On qwen35 the common prefix is computed the same way and
then *discarded* down to a checkpoint. Reproducing a cache question on a
different architecture proves nothing about this one.

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

- **Generation: 92.8 tok/s** after the fix, so checkpoint spacing costs nothing
  measurable on the generation path. (An earlier 77 tok/s figure was taken on a
  ~28-token prompt and is not comparable.)
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

## What is not solved

Two things, neither blocking.

**No pinning.** Eviction is FIFO (`erase(checkpoints.begin())`) with no way to
mark a checkpoint permanent. The ideal — pin the system prefix forever, keep one
more for the live conversation — has no expression in the API. 32 checkpoints at
128 minimum spacing is enough headroom that a voice conversation never evicts
the prefix, but that is headroom, not a guarantee.

**An unexplained 250 ms.** A fresh conversation costs 437 ms against a 185 ms
floor. If it were landing on the user-boundary checkpoint at the end of the
prefix, the rollback would be ~0 tokens and the gap should be tens of ms. So
either restoring a checkpoint is itself expensive (a state copy back into the
context), or it is landing on an earlier checkpoint than intended. The log
distinguishes these — it reports both checkpoint sizes and which one is
restored:

    journalctl -u ollama --since "10 min ago" | grep -i checkpoint

If it is restore cost, lowering min_step further will not help and the remaining
win would have to come from not needing a rollback at all.
