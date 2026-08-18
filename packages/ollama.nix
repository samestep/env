# ollama, patched so that llama-server can cache the part of a prompt that does
# not change between requests. Worth about 1.7 s per voice command; the whole
# story is in ./prefix-cache-findings.md.
#
# Takes the base package rather than pkgs, so a caller can pass ollama-cuda,
# ollama-vulkan, or plain ollama on a Mac.
ollama:

ollama.overrideAttrs (old: {
  # llama-server can place a context checkpoint exactly where a message begins,
  # but only if it is told where that is: it scans the prompt for the delimiter
  # strings in the request's "message_delimiters" field. llama-server's own
  # chat-completions path fills that in from the chat template, but ollama
  # renders qwen's template itself in Go and posts a flat string to /completion,
  # leaving the field empty. So llama-server sees an opaque prompt and falls
  # back to checkpointing near the end of it, which is a position that moves
  # with every request and can therefore never be reused.
  #
  # The patch has renderers report their delimiters and threads them through.
  # It also replays the empty think block in history, without which a follow-up
  # turn does not match the tokens the model actually produced.
  patches = (old.patches or [ ]) ++ [ ./ollama-message-delimiters.patch ];

  # This one is against llama.cpp, not ollama. nixpkgs pre-stages llama.cpp into
  # $TMPDIR/llama-cpp-src at the end of postPatch so the CMake FetchContent step
  # does not reach the network, which is the only place to get at it.
  #
  # Note nixpkgs pins b10091 while ollama 0.32.13 asks for b10380: read b10091
  # when reasoning about llama-server's behaviour here.
  postPatch = (old.postPatch or "") + ''
    patch -d "$TMPDIR/llama-cpp-src" -p1 < ${./llama-checkpoint-dedup.patch}
  '';
})
