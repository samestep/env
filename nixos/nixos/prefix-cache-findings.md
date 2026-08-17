Status: **fixed and verified.** Fresh-conversation prefill 1770 ms -> 437 ms
from checkpoint spacing, then -> 192 ms with the delimiters patch, which is the
per-request floor. Generation 94.4 tok/s, no regression.

| | original | spacing | + delimiters | + dedup | + unique marker | + VRAM |
|---|---|---|---|---|---|---|
| fresh conversation | 1770 ms | 437 ms | 192 ms | 158 ms | 165 ms | **105 ms** |
| follow-up turn | 1831 ms | 185 ms | 275 ms | 239 ms | 154 ms | **109 ms** |
| generation | 90.7 tok/s | 92.8 | 94.4 | 87.1 | 85 | **86** |

Generation varies +/- 8% run to run (77 to 94 across the session on identical
prompts), so none of that column is a signal beyond "no regression".

The follow-up turn got *worse*, 185 -> 275 ms. Explained below: it saves one
more checkpoint than a fresh conversation does. Still a good trade -- a two-turn
exchange went 437 + 185 = 622 ms to 192 + 275 = 467 ms, and voice commands are
mostly single-turn.

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

### The delimiter is not "the user tag", it is "the end of the invariant part"

`<|im_start|>user\n` is not special here — it was just the string that happened
to mark the boundary while nothing before it varied. The rule is: **place the
delimiter wherever the prompt stops being identical between requests.**

Put a per-request timestamp at the end of the system prompt and the boundary
moves earlier, so the delimiter has to move with it — not the timestamp. Hence
`OLLAMA_MESSAGE_DELIMITERS`, a JSON array of strings that overrides the
renderer's default without a recompile.

Declare exactly one. Declaring both the marker and the user tag would put a
second checkpoint *after* the timestamp, which is invalidated and re-saved every
request — the ~100 ms this is all trying to avoid.

**Matching is on token sequences, not text** (`std::equal` over the tokenized
delimiter, `common/chat.cpp`). `<|im_start|>` was safe because a special token
always tokenizes as one unit. A plain-text marker only works if it tokenizes the
same standalone as it does in context, and BPE gives no guarantee of that —
merging with a preceding newline is the obvious hazard. So a marker change must
be checked by measurement: a fresh conversation prefills in ~160 ms when the
marker matches and ~1800 ms when it does not.

### The n_ubatch red herring

Because the fallback window is one `n_ubatch`, shrinking it does buy prefill:
437 ms at 512, 310 ms at 256, 262 ms at 128, against bulk prefill dropping from
1769 to 1534 tok/s. That is a real trade, and it is the wrong thing to trade: it
tunes the granularity of the fallback instead of using the mechanism that exists
for saying where the checkpoint goes. **Do not set num_batch for this.**

## min_step must be 0, not merely small

`checkpoint_min_step` throttles creation, but it also drives an eviction pass in
`create_checkpoint` that erases any checkpoint within min_step of an earlier
one. At the 8192 default every checkpoint in a 3300-token prompt qualifies, so
the boundary checkpoint was deleted immediately after being made. 0 is
documented as "no minimum" and is the correct value now that we say where
checkpoints belong.

## What is still not solved

**No pinning.** Eviction is FIFO (`erase(checkpoints.begin())`) with no way to
mark a checkpoint permanent. The ideal -- pin the system prefix forever, keep
one more for the live conversation -- still has no expression in the API. 32
checkpoints at 128 minimum spacing is enough headroom that a voice conversation
never evicts the prefix, but that is headroom, not a guarantee.

## Where the remaining ~190 ms goes

Not prefill. The cost is nearly independent of prompt length:

| system prompt | fresh prefill |
|---|---|
| 6298 tokens | 198 ms |
| 568 tokens | 179 ms |

It is **checkpoint creation**. The recurrent state is a fixed ~162 MiB
regardless of context length, and saving one means copying that device->host.
From the log, a fresh conversation restores one checkpoint and creates two; a
follow-up restores one and creates three, because its prompt contains two user
delimiters plus a `near_prompt_end`. Solving across the two cases:

- **checkpoint save: ~65 ms** (2 saves = 192 ms fresh, 3 saves = 275 ms follow-up)
- **checkpoint restore: single-digit ms** — the cheap direction, host->device
- everything else: ~50 ms

So restores are nearly free and saves dominate. This also means the earlier
"~0.15 s of fixed per-request overhead" in the traps section was mostly
misattributed: it was checkpoint saves, not HTTP and tokenization.

### Keeping checkpoints in VRAM

The 65 ms is a device->host copy, and nothing requires that. llama.cpp has the
flag already, in `include/llama.h`:

    // Keeps the tensor data on device buffers (i.e. not accessible in host memory, but faster save/load).
    // Getting the state for a seq_id with this flag invalidates all prior states gotten for that seq_id with this flag.
    #define LLAMA_STATE_SEQ_FLAGS_ON_DEVICE 2

It is a bit flag; the server passes only `PARTIAL_ONLY` (= 1). `grep ON_DEVICE
tools/server/ common/` returns nothing — implemented in the core, never wired
up. A save would become a device->device copy via `llama_io_write_device`,
sub-millisecond instead of 65 ms.

The catch is the second comment line. `mem_storage` is
`std::map<llama_seq_id, llama_memory_buffers>` and each `get_data` rebuilds the
entry, so there is exactly **one on-device snapshot per seq_id**. Two
VRAM-resident checkpoints need two sequence ids — the two-slot design, with a
real mechanism behind it. ollama passes `-np 1`.

This is an upstream llama.cpp change, not a flag and not an ollama patch: the
checkpoint deque holds up to 32 entries and would need to know which one gets
the single on-device slot per sequence. Worth ~130 ms of the 192 ms.

### The other lever is architectural

For single-turn voice, the `near_prompt_end` checkpoint is pure overhead — we
always restore the user-boundary one. Suppressing it would save ~65 ms per
command. But `near_prompt_end` has no flag: it is exempt from
`checkpoint_min_step` and unaffected by `n_ctx_checkpoints`, so this needs a
llama.cpp patch, not a configuration change, and it would trade away multi-turn
performance (that checkpoint is exactly what a follow-up restores).

Not worth it at ~65 ms against a 1.4-3.2 s voice interaction. Recorded so the
next person does not go looking for a config knob that does not exist.

## Date and time

Neither of Home Assistant's built-in options is good. Templating the time into
the system prompt puts it inside the cached region and invalidates it on every
request; `GetDateTimeTool` costs an entire extra round trip through the model.

The third option is to state the time in the prompt but put it *after* the cache
boundary, and move the delimiter to match. The system prompt ends with

    Current time: {{ now().strftime('%Y-%m-%d %H:%M') }}

**A plain-text marker was the wrong call.** Matching is on token sequences
(`std::equal` over the tokenized delimiter), so a text marker only works if it
tokenizes the same standalone as in context — and worse, ordinary prompt text
could contain it by accident. `<|im_start|>` was safe precisely because it is a
single special token, and that property is the requirement, not an incidental
detail.

So the time is emitted as **its own system block**, by the renderer, right after
the invariant part:

    ...<entity list><|im_end|>\n<|im_start|>system\nCurrent time: 2026-08-17 03:41<|im_end|>\n<|im_start|>user\n...

with the marker `<|im_end|>\n<|im_start|>system\n`. That cannot be spelled by
prompt text, and it cannot match at position 0, where no message precedes the
first one. `OLLAMA_TIME_FORMAT` is a Go time layout and turns the block on;
unset leaves upstream behaviour.

Putting it in the renderer rather than in Home Assistant's prompt keeps the
marker and the thing it marks in one repo. Home Assistant's prompt lives in its
storage, outside any rebuild, which is exactly how the two would drift apart.

### The delimiter must END on a special token

It does not. Measured with `prompt_eval_count` as a tokenizer oracle — for a
single user message the rendered prompt is a constant plus the content's tokens,
so `tokens(x)` is recoverable and `tokens(x+y) == tokens(x) + tokens(y)` answers
"does this junction merge":

    system\n     tokens = 1 + 20  vs together 22   MERGES
    system\n\n    tokens = 1 + 20  vs together 22   MERGES
    time\n       tokens = 1 + 20  vs together 22   MERGES

`system\n` is a single token standalone and splits when text follows it, so
`<|im_end|>\n<|im_start|>system\n` never matched and fresh conversations fell
back to end-of-prompt checkpoints: 158 ms -> 527 ms.

Special tokens are atomic and merge with nothing on either side, so the marker
is now `<|im_end|>\n<|im_start|>` — 3 tokens, and additive against every message
type that can follow it:

    3 + 22 vs 25  CLEAN   + 'system\nCurrent time: ...'
    3 +  7 vs 10  CLEAN   + 'user\nTurn on the lamp.'
    3 +  4 vs  7  CLEAN   + 'assistant\nOkay.'

**Any future marker must be checked this way.** Reasoning about BPE is not
enough; this one looked obviously fine and was not.

### And it must be unique, not merely stable

`<|im_end|>\n<|im_start|>` is stable but matches *every* message boundary, and
a snapshot is taken at each: fresh prefill 267 ms against 158 ms for a marker
that matched one place. The dedup patch does not save us here, because the
boundaries in question are at positions that genuinely differ per request.

So the marker is `<|fim_pad|>` — a single special token, emitted by the renderer
in exactly one place. Every spare special token in this vocab was checked and
all tokenize as one token; a padding token was chosen because it carries no
meaning the model has to interpret.

Both properties are required, and only a special token has both: text markers
fail to match at all, and structural markers match too often.

The dedup remains sound even though the timestamp makes content change under a
fixed position: on any divergence the server first erases every checkpoint with
`pos_max > pos_next`, so a checkpoint that survives to be dedup-matched was
necessarily built from an identical token prefix.

## nixpkgs builds a different llama.cpp than ollama pins

`pkgs/by-name/ol/ollama/package.nix`:

    # Pre-stage the pin (tracks upstream's `LLAMA_CPP_VERSION` file) ...
    llamaCppVersion = "b10091";

ollama 0.32.13's `LLAMA_CPP_VERSION` says **b10380**. The comment claims the pin
tracks upstream; it is roughly 290 builds behind.

Our patch is unaffected — `message_delimiters` exists in both, which is why the
measurement came out right — but **read b10091 when reasoning about behaviour on
this host**, not ollama's pin and not llama.cpp master. All three differ.


## The real per-request floor is ~56 ms

Send the *same* tiny prompt repeatedly. After the first, there is nothing new to
evaluate and (with the dedup patch) no new checkpoint position, so what is left
is the cost of being a request at all:

    identical request 0: prefill  141.3 ms / 15 tok     <- new prompt, takes a checkpoint
    identical request 1: prefill   55.9 ms / 15 tok
    identical request 2: prefill   56.9 ms / 15 tok
    identical request 3: prefill   55.1 ms / 15 tok

So **~56 ms is irreducible** without changing ollama or llama.cpp more deeply,
and a fresh conversation at 158 ms still carries ~100 ms of checkpoint work: one
save plus one restore.

Do not try to attribute that 100 ms more finely than this. Several attempts at
solving for per-save and per-restore costs from differences between measurement
types gave inconsistent answers (65 ms, then 35 ms, then 85 ms) because the
cases differ in token count and checkpoint count at the same time. The reliable
statements are the four measured totals in the table and the ~56 ms floor.


## Measurement hygiene, again

The trap at the top of this document ("Home Assistant must be idle") was
violated by running a latency microbenchmark concurrently with a 75-run eval.
It corrupted both: the microbenchmark read 234 ms for an identical request
(higher than a real 3300-token conversation), and the eval reported the date
scenario at 10.3 s when it actually takes 0.5-0.7 s.

Nothing on this host measures anything while anything else is running. That
includes background tasks started earlier in the same session.

## The time format needs the weekday

`OLLAMA_TIME_FORMAT` states the weekday explicitly. Given only `2026-08-17` the
model answered "Sunday" and then "Monday" for the same question on consecutive
requests. It is a Monday. Deriving a weekday from a date is arithmetic the model
does unreliably, and it costs nothing to hand it over.


## Why follow-up turns were rewinding

They should not have been. Continuing a conversation is appending, and appending
needs no rollback. The cause was a prompt-rendering mismatch, found by rendering
both turns with ollama's own renderer and diffing them:

    common tail : ...the kitchen lamp.<|im_end|>\n<|im_start|>assistant\n
    turn 1 then : <think>\n\n</think>\n\n
    turn 2 then : The kitchen lamp is on.<|im_end|>\n<|im_start|>user\n...

With thinking off, the qwen3.5 renderer ends the generation prompt with an empty
`<think>\n\n</think>\n\n` (`emitEmptyThinkOnNoThink`), so the model's reply
physically follows it in the slot. Replaying that same turn as history omits the
block, so the shared prefix ends at `assistant\n` and everything after is
recomputed — which on this architecture means a checkpoint rollback, not merely
wasted prefill.

The patch replays the empty block in history. Verified: the turn-2 prompt now
has the turn-1 prompt as an exact prefix, diverging only where new content
begins.

**An earlier attempt to test this concluded the opposite and was wrong.** It
compared `think=false` against `think=true` with the thinking field preserved --
a different code path -- saw 247 ms vs 245 ms, and cleared the think tags of
suspicion. The two paths differ in where the block is emitted, not whether it is.
Render and diff the actual strings; do not infer from latency.
