# Development stack

A second Home Assistant, running in the agent VM, so voice work does not need a
rebuild of the real machine for every experiment.

    dev/run-ha.sh                    # start it (builds .#hass-dev if needed)
    python3 dev/ha-onboard.py        # once, on an empty config dir
    python3 dev/ha-setup.py          # configure it; idempotent
    python3 dev/ha-ask.py "is the bed light on?"
    dev/run-ha.sh stop

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
