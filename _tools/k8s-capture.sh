#!/usr/bin/env bash
# Capture helper: records each command and its real output into a log file.
# Used to produce the .txt logs (and, from those, the rendered PNGs) for
# the Kubernetes sessions. Sourced by the per-task capture scripts.

LOG=""

init_log() {
  LOG="$1"
  mkdir -p "$(dirname "$LOG")"
  : > "$LOG"
}

# run "<command string>"  -- prints a shell-style prompt line, then real output.
run() {
  printf '$ %s\n' "$1" >> "$LOG"
  # shellcheck disable=SC2086
  eval "$1" >> "$LOG" 2>&1
  printf '\n' >> "$LOG"
}

# note "<text>" -- inserts a commentary line into the transcript.
note() {
  printf '# %s\n' "$1" >> "$LOG"
}
