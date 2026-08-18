# Development stack

A second Home Assistant, running in the agent VM, so voice work does not need a
rebuild of the real machine for every experiment.

    dev/run-ha.sh                    # start it (builds .#hass-dev if needed)
    python3 dev/ha-onboard.py        # once, on an empty config dir
    python3 dev/ha-setup.py          # configure it; idempotent
    python3 dev/ha-ask.py "is the bed light on?"
    dev/run-ha.sh stop

Voice and model experiments, all driven through `dev/halib.py`. See
`dev/semantic-endpointing.md` for what they found:

    dev/turn-test.py <clip>          # does it keep listening through a pause?
    dev/silence-sweep.py             # latency against pause tolerance
    dev/stage-breakdown.py           # where the milliseconds go
    dev/e2e-compare.py               # old settings against new
    dev/eval.py 3 <model>...         # scenario scores, state reset each run
    dev/model-compare.py             # models, end to end
    dev/toolcall-stress.py           # the tool-call path, repeatedly
    dev/smart-turn-probe.py <clip>   # the turn model's opinion, cut by cut
    dev/smart-turn-eval.py           # its accuracy on real labelled speech

Anything that streams audio needs a transcriber in this VM, because the host's
is bound to loopback:

    $(nix build --no-link --print-out-paths nixpkgs#wyoming-faster-whisper)/bin/wyoming-faster-whisper \
      --model tiny-int8 --language en --uri tcp://127.0.0.1:10300 \
      --data-dir ~/ha-dev/whisper --download-dir ~/ha-dev/whisper

`stt.demo_stt` cannot stand in for it: it accepts only stereo and the pipeline
sends mono.

State lives in `~/ha-dev`, the token in `scratch/hadev/token.txt`. Delete the
directory to start over; the three scripts rebuild everything.

## What runs where

Only two things need the GPU, and they stay on the NixOS host:

| | where | why |
|---|---|---|
| ollama | host | CUDA, and the model is 28 GiB |
| Kokoro TTS | host | CUDA |
| Home Assistant | **here** | no GPU; this is what we iterate on |
| faster-whisper, openWakeWord | either | CPU; ~90 ms to transcribe |

The dev instance talks to the host's ollama at `192.168.122.1:11434`, which is
open on `virbr0`. The host's speech services are bound to loopback and are not
reachable from here; run local ones if a test needs them.

## Things that cost an hour to find

- The package is pinned to **nixpkgs-stable**, matching the host. The Silero
  patch does not apply to Home Assistant 2026.8.2 in unstable. A dev instance on
  a different version teaches you nothing transferable.
- `extraComponents` does not change the derivation. The NixOS module passes the
  component dependencies through `environment.PYTHONPATH = package.pythonPath`,
  which is why `.#hass-dev` is a wrapper that exports it.
- The module also always adds `defaultIntegrations`, including **frontend**.
  Without it `hass_frontend` is missing, frontend setup fails, and Home
  Assistant silently drops into **recovery mode** -- which ignores
  `configuration.yaml`, so nothing loads and the failure looks like anything but
  a missing frontend.
- Do not use `default_config:`; it pulls dhcp, go2rtc, logbook, my, ssdp and
  stream, and taking everything it would have set up down with it when they are
  missing.
- `pkill -f hass` matches the shell running it. Use the bracketed pattern in
  `run-ha.sh`.

## More things that cost an hour to find

- **Websocket ids must increase.** Home Assistant rejects a lower id with
  `id_reuse`, so `halib` hands them out centrally rather than letting callers
  pick.
- **Do not truncate `hass.log` while Home Assistant holds it open.** The write
  offset stays where it was and the file fills with nul bytes, so `grep` finds
  nothing and the log looks empty. Restart it instead.
- **Subentry ids are not in the REST entry listing**, which reports only
  `num_subentries`. They come from `config_entries/subentries/list` over the
  websocket.
- **Turn-detection verdicts log at debug level.** Without the `logger:` block in
  `configuration.yaml` the decision is invisible and you can only infer it from
  timing.
