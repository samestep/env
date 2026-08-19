#!/usr/bin/env bash
# Start or stop the ollama request tap. A script, not a one-liner, because
# `pkill -f` on the name also matches the shell that typed it.
set -euo pipefail
cd "$(dirname "$0")/.."
pidfile=scratch/ollama-tap.pid
if [ "${1:-start}" = stop ]; then
  [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null && echo stopped || echo "not running"
  rm -f "$pidfile"; exit 0
fi
if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
  echo "already running as $(cat "$pidfile")"; exit 0
fi
setsid dev/py dev/ollama-tap.py > scratch/ollama-tap.log 2>&1 < /dev/null &
echo $! > "$pidfile"
sleep 6
cat scratch/ollama-tap.log
