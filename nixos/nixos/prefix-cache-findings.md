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

## Where the remaining time went, and how it was closed

Cost is nearly independent of prompt length. A repeated *identical* request
diverges nowhere, so it never restores:

    identical large request: 57.9 ms / 6326 tok
    identical small request: 57.3 ms /   45 tok

**~57 ms is the irreducible per-request cost.** Everything above that was one
checkpoint restore plus the genuinely new tokens.

Earlier versions of this section attributed the gap to checkpoint *saves*
("~65 ms each, restores single-digit"). That was derived from comparing
measurements that differed in two things at once and is **withdrawn**. Restores
were the expensive half.

## Keeping the checkpoint in VRAM

`llama.cpp` has had the flag since #22679 and nothing in the tree used it except
a test:

    // Keeps the tensor data on device buffers (i.e. not accessible in host memory, but faster save/load).
    // Getting the state for a seq_id with this flag invalidates all prior states gotten for that seq_id with this flag.
    #define LLAMA_STATE_SEQ_FLAGS_ON_DEVICE 2

It is a bit flag; the server passed only `PARTIAL_ONLY` (= 1). Passing both for
the prompt checkpoint's save and restore keeps the snapshot in device buffers
instead of copying it across PCIe each way. Measured: **165 ms -> 105 ms** on a
fresh conversation.

### It is only safe with exactly one checkpoint

`mem_storage` is `std::map<llama_seq_id, llama_memory_buffers>` and every save
resolves to the same entry for a given sequence, silently overwriting the
previous snapshot's data while the server still holds that checkpoint and will
still restore from it. ollama runs `-np 1`, so there is one sequence.

**The first attempt shipped with this invariant broken.** Suppressing
end-of-prompt checkpoints only covered mid-prompt batches; the fully-processed
branch still took one, so two existed (at 3260 and 3300) and the second
clobbered the first. Both branches are suppressed now.

Verified from the log — five fresh conversations in a six-second window:

    task 351 | created context checkpoint 1 of 32 (pos_min = 6283)
    task 369 | restored ... reusing context checkpoint (pos_min = 6283)
    task 374 | restored ... reusing context checkpoint (pos_min = 6283)
    task 380 | restored ... reusing context checkpoint (pos_min = 6283)
    task 388 | restored ... reusing context checkpoint (pos_min = 6283)

One checkpoint, created once on the cold request, reused thereafter.

**Bound that window to known traffic.** A ten-minute window spanning a
`nixos-rebuild switch` counted 8 creations and looked like a failure, because it
included the previous build.

### How to check it, and how not to

This failure mode makes latency *better* — the broken build read 99 ms — so no
timing measurement can detect it. Check, in this order:

1. `journalctl -u ollama --since <exact> --until <exact> | grep "created context
   checkpoint 2 of"` must be empty.
2. `prefix-cache-statecheck.py` must still answer *correctly*: eight fresh
   conversations against a 300-device prompt at temperature 0.
3. Latency, last.

**Compare the answers, not the digest.** The digest changed when this landed
(`4c4a1573` -> `1eed9fb1`) and the state was fine: seven of eight answers
byte-identical, the eighth differing only by markdown emphasis (`**on**` ->
`on`). Changing checkpoint placement changes batch shapes, hence float
arithmetic, which can flip a near-tie token with perfectly correct state. A real
wrong-state restore shows up as wrong *facts*. The digest is a trigger to look,
not a verdict. The test is deterministic within a build: two consecutive runs
gave identical digests.

An earlier note here claimed two quoted answers proved corruption. They did not
— the model reports the minutes field rather than computing minutes since
midnight, on any build. Retracted.

## What is still not solved

**No pinning.** Eviction is FIFO (`erase(checkpoints.begin())`) with no way to
mark a checkpoint permanent. It does not bite while exactly one checkpoint
exists, but nothing enforces that beyond the two suppressions above.

**Follow-up turns still restore rather than purely appending**, landing a few
tokens short of the boundary. Worth a look if the ~109 ms ever matters.


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


## End-to-end latency, measured (August 2026)

Real audio through the whole pipeline, streamed at real time. Timed from the
moment the user stops speaking, which is what they actually feel:

| stage | simple command | question needing state |
|---|---|---|
| VAD silence window + end-of-speech | ~1.05 s | ~1.05 s |
| STT transcribe (faster-whisper, CPU) | ~0.10 s | ~0.10 s |
| conversation agent | 0.003 s (local matcher) | 1.4-2.0 s (LLM + tool round trip) |
| TTS (Kokoro, GPU) | ~0.13 s | ~0.13 s |
| **total** | **~1.3 s** | **~2.7-3.3 s** |

Prompt prefill, the subject of this entire document, is now 0.105 s of that.

**The VAD silence window dominates simple commands** and is a setting, not
compute. **A tool round trip dominates questions** — asking the model for the
temperature costs a full extra generate-and-reply cycle.

STT compute is ~0.10 s, about 6% of a simple command. Moving faster-whisper to
the GPU might halve it, saving ~0.05 s against a 1.05 s VAD window. Not the
place to spend effort.

## Model choice: generation now dominates, so the calculus flipped

Same system prompt, fresh conversation, plus a realistic ~18-token reply:

| model | prefill | generation | short reply |
|---|---|---|---|
| qwen3.6:27b-mtp-q8_0 (current) | 106 ms | 85 t/s | 317 ms |
| qwen3.8:27b-mtp-q8_0 | 106 ms | 88 t/s | 310 ms |
| qwen3.8:27b-mtp-q4_K_M | 79 ms | 105 t/s | 251 ms |
| qwen3.6:27b-q4_K_M | 72 ms | 39 t/s | 531 ms |
| qwen3.6:35b-a3b-q4_K_M | 36 ms | 168 t/s | **144 ms** |
| ornith:35b-q4_K_M | 35 ms | 179 t/s | **135 ms** |
| muse-glimmer:30b-q4_K_M | 63 ms | 40 t/s | 509 ms |

The dense 27B was chosen when prefill cost 0.65-1.8 s, on the reasoning that
"generation speed is not the binding constraint for voice anyway". That was true
then and is false now: prefill is 0.1 s and generation is the rest. The MoE
models are 2.3x faster end-to-end on the LLM stage.

Both fast models are `qwen35moe`, `full_attention_interval: 4` — the same hybrid
architecture, so everything here applies to them too.

**Blocker before switching:** qwen35moe was rejected earlier for a CUDA illegal
memory access during constrained decoding of tool calls with array/enum
parameters, which is exactly what Home Assistant sends. That was on ollama
0.32.3; we are on 0.32.13. Re-test before trusting it.


## Home Assistant's own overhead is ~3.7 ms

A locally-matched command runs the whole pipeline with no model involved:
websocket in, sentence matching, service call, events out.

    intent stage (matcher + service call):   2.44 ms
    whole request, socket to run-end     :   3.67 ms

There is nothing to optimise there. An earlier estimate of "~300 ms of HA
plumbing" was wrong: it subtracted HA's end-to-end time for the real prompt
(~1848 tokens, full Assist tool schemas) from a synthetic replication (~250
tokens, four toy tools). The residual is model work on a bigger prompt, not
overhead. Do not subtract across measurements with different prompts.

## Tool round trip: 478 ms, measured like for like

Same prompt, same tools, same model, question "Is the bed light on?":

| | prefill | generate | total |
|---|---|---|---|
| call 1, emit tool call | 91.7 ms | 327.5 ms (29 tok) | 419 ms |
| call 2, answer from result | 100.8 ms | 157.5 ms (10 tok) | 258 ms |
| **two-call total** | | | **677 ms** |
| single call, state in prompt | 91.5 ms | 107.9 ms (9 tok) | **199 ms** |

The saving is 478 ms, of which 327 ms is generating the tool call itself.

The trade is ~29 generated tokens for ~60 prefilled ones. Generation runs at
~85 tok/s and prefill at ~1750 tok/s, so a prefilled token is ~20x cheaper --
twice the tokens for a tenth of the time.

Home Assistant's prompt field is a Jinja template and a `<|fim_pad|>` typed into
it tokenizes as the special token (verified: +1 token, against +4 for text of
the same length). So HA can supply the boundary marker and everything after it,
which is what makes this possible without further patching.


## Home Assistant assembles the prompt in the wrong order for caching

`chat_log.py` builds the system prompt as:

1. the configured prompt template
2. `llm_api.api_prompt` -- the API preamble plus a YAML dump of every exposed
   entity
3. the date and time, but only when no `GetDateTime` tool is offered
4. `extra_system_prompt`

So the entity overview lands *after* the template. A boundary marker at the end
of the template would leave that overview -- 300-400 tokens that never change --
outside the cached region, re-read on every request for around 200 ms. That is
not the "inline these entities, tool-call for the rest" tradeoff; it is pure
waste.

`home-assistant-cache-boundary.patch` splits the template on the marker and
appends the tail last, giving:

    unchanging instructions, preamble, entity overview | marker | time, live states

Note point 3: Home Assistant already injects the date and time itself, and
suppresses it only because the Assist API offers `GetDateTimeTool`. Dropping
that tool would get the time for free -- but into part 3, which is *before* the
marker after this patch, so it would invalidate the cache every minute. Put the
time after the marker instead.


## Result: live state in the prompt, measured end to end

Home Assistant's prompt now ends with the marker followed by the current time
and the live state of the entities worth stating up front. Through the real
pipeline, intent stage:

| question | tool round trip | state in prompt |
|---|---|---|
| Is the bed light on? | 986 ms | **433 ms** |
| What is the weather forecast? | 1265 ms | **585 ms** |
| Turn on the ceiling lights (local matcher) | 3 ms | 4 ms |
| unanswerable, falls through to search | 1754 ms | 1355 ms |

Answers verified against the entity states rather than just timed: bed light
off, kitchen lights on, weather partlycloudy 79 F humidity 81%, all reported
correctly and with no tool call.

The prompt is now:

    <instructions>                      cached
    <API preamble, entity overview>     cached, thanks to the chat_log patch
    <|fim_pad|>                         the boundary
    Live state, correct as of now:      re-read each request, ~60 tokens
    Current time: ...
    Bed Light: ... etc

Exactly one marker exists in the prompt, which is what keeps the on-device
snapshot safe. The renderer no longer injects one.


## The VAD wait, measured properly

Streaming silence continuously rather than ending the stream, timed from the
last sample of speech:

    end of speech -> stt-vad-end (VAD decides)    1206 ms
    end of speech -> stt-end   (+ transcribe)     1301 ms
    transcription alone                             94 ms

**Transcription is 94 ms.** faster-whisper on CPU is not worth moving to the
GPU; it is 5% of a voice interaction. An earlier "~0.10 s" figure for this was
right, and a later "~600 ms" inference from a fast-push harness was wrong.

**The VAD decision is 1206 ms** and is now the single largest cost in the whole
pipeline. `AudioSettings.silence_seconds` defaults to 0.7 s, so roughly 500 ms
of that is unaccounted for and worth chasing before touching the threshold.

`silence_seconds` is **not settable over the websocket API**. The handler builds
`AudioSettings` from only `noise_suppression_level`, `auto_gain_dbfs`,
`volume_multiplier` and `is_vad_enabled` (`websocket_api.py:211`), so a run
request cannot override it. Calling it "just a setting" was wrong: it is a
constant with no UI and no API, and changing it means another Home Assistant
patch.


## Chasing the extra VAD time: partly explained

The utterance really is speech from 50 ms to 1240 ms of a 1280 ms file, checked
by looking at the samples, so no leading or trailing silence is confusing this.

Streaming it in real time and timing against my own clock:

| | measured | expected from settings |
|---|---|---|
| speech onset -> `stt-vad-start` | 1007 ms | 350 ms (50 + speech_seconds 300) |
| end of speech -> `stt-vad-end` | 1206 ms | 700 ms (silence_seconds) |

Both ends were late by roughly the same ~600 ms, which looks like a constant
delay in the audio path.

Prepending 2 s of silence before the utterance moves onset to **605 ms** after
speech begins, against 1007 ms without. So roughly 400 ms is Home Assistant
pipeline startup: it is not ready to consume audio the instant the run begins,
and early audio queues behind that.

**This probably does not apply to a real satellite.** A wake-word device starts
the pipeline when it hears the wake word, before the command is spoken, so that
startup is absorbed. My harness starts the run and streams immediately.

**Unexplained: the end is still ~600 ms late even with startup absorbed** (1305
ms against ~700 ms expected), while onset improved. An asymmetric residual is
not a constant pipeline delay, so that explanation does not cover it. Thresholds
do not obviously explain it either: `in_command_speech_threshold` is 0.5 and the
silence being fed is digital zero, which should read as ~0 immediately. Likely
candidates not yet tested: smoothing or internal state in the VAD model itself,
or buffering between the websocket handler and the pipeline.

Actionable regardless: `silence_seconds` is 0.7 and unreachable from the API, so
lowering it needs a patch. That is worth doing after the residual is understood,
not before -- otherwise a smaller threshold may just be swallowed by whatever
the extra 600 ms is.


## The unexplained VAD time was the VAD model's hangover

Running `pymicro_vad.MicroVad` -- the model Home Assistant uses, over 10 ms
frames -- directly on the same utterance followed by digital silence:

        0 ms after speech end: 1.000
      300 ms after speech end: 1.000
      500 ms after speech end: 0.941
      600 ms after speech end: 0.920
      700 ms after speech end: 0.009

    first frame at or below the in-command threshold (0.5): 640 ms

It holds probability at 1.000 for 400 ms after the audio is silent and does not
fall below the threshold until 640 ms. HA's `silence_seconds` countdown only
starts once it does.

So the 1306 ms measured from end of speech to `stt-vad-end` is
**VAD hangover + silence_seconds**, and both parts are now accounted for.
(The 640 ms figure came from one clip; see the multi-source measurement below.) Nothing is lagging: HA's own audio timestamps track wall clock,
so the pipeline keeps up in real time.

This makes lowering the threshold safer than it first appears. Tolerance for a
mid-sentence pause is hangover + silence_seconds, and a pause shorter than 640 ms
never registers as silence at all. `home-assistant-vad-silence.patch` sets it to
0.4, giving 1040 ms of tolerance and taking 300 ms off every command.

The 640 ms floor belongs to the model. Beating it means a different VAD, not a
different setting.


## The hangover is real, and not a TTS artefact

The 640 ms above rested on a single Piper clip, which is not enough to tell
"this model always hangs on" from "this model mishandles unnaturally clean
synthetic audio". Two controls:

**Noise floor makes no difference.** Same utterance, varying what follows it,
and with noise mixed through the speech as a real microphone would:

    digital zero          640 ms      noise rms 32  everywhere   640 ms
    noise rms 32          640 ms      noise rms 100 everywhere   640 ms
    noise rms 1000        630 ms      noise rms 300 everywhere   640 ms

**Real human speech behaves the same.** Cutting each clip mid-word, so speech is
unambiguously ongoing at the cut, then feeding silence:

| source | median release |
|---|---|
| REAL: JFK, 1961 | 480 ms |
| REAL: LDC/TIMIT sentence | 600 ms |
| TTS: Piper en-us-ryan-medium | 580 ms |
| TTS: Kokoro | 530 ms |

So it is inherent to the model, roughly **340-610 ms** depending on the clip,
and the single-clip 640 ms was at the high end. Others have hit this: rhasspy
/pymicro-vad issue 1 is exactly "vad end takes more time compared with the old
one", from when Home Assistant 2024.8 switched to micro_vad.

Method note: "release after the last audible sample" is not a sound measurement.
It gave JFK 0 ms, because a noisy recording's tail is audible without being
speech. Cut mid-speech instead.

The remaining lever is a different VAD. Silero releases far faster and exposes a
minimum-silence parameter. That is a bigger patch than a constant, but it is
where the floor actually is.


## Why the model behaves this way: it is a wake-word model

pymicro-vad's README says it "uses the machine learning architecture from
microWakeWord". That is a *wake word* architecture: a classifier over a sliding
window, answering "does this window contain the phrase". Used as a VAD it
answers "does this window contain speech", which is inherently about one window
late at both edges.

Feeding bursts of real speech of varying length, surrounded by silence:

    burst   peak prob during burst   stays above 0.5 after
     50 ms          0.00             never fires
    100 ms          0.00             never fires
    200 ms          0.00             never fires
    300 ms          0.06             never fires
    500 ms          1.00             650 ms
    800 ms          1.00             650 ms
   1200 ms          1.00             540 ms

Under ~400 ms of speech never registers at all, and once it fires it holds until
the window drains. That is a ~500 ms window, and it explains both edges we
measured: onset ~340 ms late, release ~340-610 ms.

**This is not a bug and not an oversight by whoever trained it.** For wake-word
detection a window-length latency is inherent and harmless -- you are detecting
a discrete event, not tracking when someone stopped talking. It only becomes a
problem when the model is repurposed to decide end-of-speech, which is what Home
Assistant does with it.

It also means no threshold can fix it. `silence_seconds` is added *after* the
model finally reports silence. The `home-assistant-vad-silence.patch` that set
it to 0.4 has been reverted for that reason: it trims the wrong term.

The fix is a different VAD. Silero is the obvious candidate: it releases in tens
of milliseconds and exposes a minimum-silence parameter. That means patching
`audio_enhancer.py`, which hardcodes `MicroVad`.
