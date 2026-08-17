Status: **fixed and verified.** Fresh-conversation prefill 1770 ms -> 437 ms
from checkpoint spacing, then -> 192 ms with the delimiters patch, which is the
per-request floor. Generation 94.4 tok/s, no regression.

| | original | spacing fix | + delimiters patch |
|---|---|---|---|
| fresh conversation | 1770 ms | 437 ms | **192 ms** |
| follow-up turn | 1831 ms | 185 ms | **275 ms** |
| generation | 90.7 tok/s | 92.8 | **94.4** |

The follow-up turn got *worse*, 185 -> 275 ms, and that is not yet explained.
The likely cause is that a new user message now triggers a checkpoint save
(~162 MiB of state), but that does not obviously square with a fresh
conversation costing only 192 ms while also starting a user message. The log
would settle it. It is a good trade either way: a two-turn exchange went
437 + 185 = 622 ms to 192 + 275 = 467 ms, and voice commands are mostly
single-turn.

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

## Telling the engine exactly where to checkpoint

The remaining 437 - 185 ms was **not** restore cost. The log showed every
checkpoint landing at a `near_prompt_end` position, 512 apart (2759 and 3271 for
a 3272-token prompt), because `near_prompt_end` opens a window of one
`n_ubatch`. The system prefix ends at 3261, just before 3271, so it fell back to
2760 and re-prefilled ~500 tokens.

That is the *fallback* placement. The intended one is `is_user_start`, and it is
directly controllable: `message_delimiters` is a field on the `/completion`
request (`server-context.cpp:4150` at b10380, the revision ollama pins):

    auto delimiters = common_chat_msg_delimiters_parse(json_value(data, "message_delimiters", json::array()));
    delimiters.tokenize(ctx_server.vocab);
    ...
    task.params.message_spans = task.tokens.find_message_spans(delimiters);

Spans are not derived from structured chat data. llama-server tokenizes the
delimiter strings you hand it and scans the prompt for them. Give it
`<|im_start|>user\n` and it puts a checkpoint at the end of everything before
the first user message -- the system prompt and tool definitions -- which is
exactly where a new conversation diverges.

ollama never sends the field. It renders qwen's template in Go and posts a flat
string to `/completion` (`llm/llama_server.go:5`), and its
`llamaServerCompletionRequest` has no such field, so llama-server parses
`json::array()` and finds no spans.

`ollama-message-delimiters.patch` adds it: an optional `MessageDelimiters()`
method on the renderer interface, implemented for `Qwen35Renderer`, threaded
through `llm.CompletionRequest` into the request body. Applies cleanly to
v0.32.13, which is what nixpkgs ships; `go build` and the `renderers` and `llm`
test packages pass.

### The n_ubatch red herring

Because the fallback window is one `n_ubatch`, shrinking it does buy prefill:
437 ms at 512, 310 ms at 256, 262 ms at 128, against bulk prefill dropping from
1769 to 1534 tok/s. That is a real trade, and it is the wrong thing to trade: it
tunes the granularity of the fallback instead of using the mechanism that exists
for saying where the checkpoint goes. **Do not set num_batch for this.**

## What is still not solved

**No pinning.** Eviction is FIFO (`erase(checkpoints.begin())`) with no way to
mark a checkpoint permanent. The ideal -- pin the system prefix forever, keep
one more for the live conversation -- still has no expression in the API. 32
checkpoints at 128 minimum spacing is enough headroom that a voice conversation
never evicts the prefix, but that is headroom, not a guarantee.
