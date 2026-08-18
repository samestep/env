# Home Assistant, patched for voice latency. See ./prefix-cache-findings.md.
home-assistant:

home-assistant.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [
    # Home Assistant builds the system prompt as: the configured template, then
    # the API preamble and the exposed entity overview, then anything extra.
    # That puts unchanging content *after* the template, so a cache boundary
    # placed at the end of the template would leave the entity overview outside
    # the cached region -- 300-400 tokens re-read on every request, about
    # 200 ms, for content that never changes. This moves everything after the
    # boundary marker to the very end instead.
    ./home-assistant-cache-boundary.patch

    # Home Assistant's own Silero VAD implementation, lifted from the commit
    # that added it (079c6daa633) before it was reverted a month later in
    # 329b2c840d8 for lag, broken end-of-speech detection, crashes and macOS
    # build failures -- problems for a project shipping to every platform.
    #
    # microVAD is a wake-word architecture classifying over a ~500 ms window, so
    # it keeps reporting speech for 480-600 ms after speech stops and needs
    # 400-500 ms before reporting any. Silero releases in 0-96 ms and fires on
    # 100 ms of speech. That is ~600 ms off every command, and it also closes
    # the band of pause lengths where the old VAD would cut you off *after* you
    # had already started speaking again.
    ./home-assistant-silero-vad.patch

    # Lets a pipeline run set silence_seconds. The websocket API already accepts
    # four of the five audio settings; this one was reachable only through the
    # VAD sensitivity select entity that satellite integrations create, so it
    # could not be tuned or tested without buying hardware.
    ./home-assistant-vad-silence-api.patch

    # Semantic endpointing. Silence alone cannot tell "still thinking" from
    # "finished" -- acoustically identical, only the words differ -- so latency
    # and pause tolerance are forced to be the same number. On reaching
    # silence_seconds this asks Smart Turn v3 whether the utterance sounds
    # complete and keeps listening if not, which separates them.
    #
    # The model must only be asked about audio that ends where speech stopped:
    # fed audio cut mid-word, 60.6% of polls read as complete, because it judges
    # the prosody up to the cut. Silero still decides *when* to ask.
    ./home-assistant-smart-turn.patch
  ];

  # audio_enhancer.py imports pysilero_vad after the Silero patch. The manifest
  # change in that patch does not pull it in, because nixpkgs resolves component
  # requirements before patches are applied -- and it has to be a package input
  # rather than services.home-assistant.extraPackages, because the test suite
  # runs during the build and imports it too.
  #
  # passthru.python3Packages is the matching interpreter's set; pkgs.python3Packages
  # would be a different Python and the import would fail at runtime.
  propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [
    home-assistant.python3Packages.pysilero-vad
    (home-assistant.python3Packages.callPackage ./smart-turn.nix { })
  ];
})
