#!/usr/bin/env bash
# Start the development Home Assistant in the agent VM.
#
#   dev/run-ha.sh            # start it in the background
#   dev/run-ha.sh stop       # stop it
#
# The real machine is untouched: this instance keeps its own state in ~/ha-dev
# and only borrows the host's ollama, which is the one part that needs a GPU.
set -euo pipefail
cd "$(dirname "$0")/.."
DIR="${HA_DEV_DIR:-$HOME/ha-dev}"

# The pattern is bracketed so it cannot match this script's own command line.
pid() { pgrep -f "bin/[.]hass-wrapped" | head -1; }

if [ "${1:-start}" = stop ]; then
  p=$(pid || true); [ -n "$p" ] && kill "$p" && echo "stopped $p" || echo "not running"
  exit 0
fi

p=$(pid || true)
if [ -n "$p" ]; then echo "already running as $p"; exit 0; fi

mkdir -p "$DIR"
cp dev/configuration.yaml "$DIR/configuration.yaml"
wrapper=$(nix build --no-link --print-out-paths .#hass-dev)
setsid "$wrapper/bin/hass-dev" -c "$DIR" > "$DIR/hass.log" 2>&1 < /dev/null &
sleep 3
echo "started $(pid) -- log: $DIR/hass.log"
