#!/usr/bin/env bash
# Start or stop the stand-in text-to-speech server.
#
#   dev/run-fake-tts.sh          # start it in the background
#   dev/run-fake-tts.sh stop
#
# It lives in a script rather than a shell one-liner because `pkill -f fake-tts`
# also matches the shell that typed it, which kills the wrong process.
set -euo pipefail
cd "$(dirname "$0")/.."
pidfile=scratch/fake-tts.pid

if [ "${1:-start}" = stop ]; then
  [ -f "$pidfile" ] && kill "$(cat "$pidfile")" 2>/dev/null && echo stopped || echo "not running"
  rm -f "$pidfile"
  exit 0
fi

if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
  echo "already running as $(cat "$pidfile")"; exit 0
fi

setsid dev/py dev/fake-tts.py > scratch/fake-tts.log 2>&1 < /dev/null &
echo $! > "$pidfile"
sleep 8
cat scratch/fake-tts.log
