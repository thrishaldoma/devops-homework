#!/usr/bin/env bash
# Usage: run.sh <logfile> <command...>
# Echoes the command, runs it, appends both to the log, and
# always returns 0 so a failing demo command cannot abort a phase.
LOG="$1"; shift
mkdir -p "$(dirname "$LOG")"
{
  echo ""
  echo "\$ $*"
  eval "$@" 2>&1
  echo "[exit: $?]"
} | tee -a "$LOG"
exit 0
