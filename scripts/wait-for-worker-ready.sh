#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: wait-for-worker-ready.sh --log-file file [options]

Poll worker log file for startup confirmation.

Options:
  --log-file      path to worker log file, required
  -p, --pattern   regex pattern to look for (default: "Worker started")
  -F, --fixed     treat pattern as a fixed string (grep -F)
  -T, --timeout   seconds to wait (integer, default: 30)
  -i, --interval  poll interval in seconds (default: 0.5)
  -h, --help      show this help
USAGE
}

log_file=""
pattern="Worker started"
grep_flag="-E"
timeout=30
interval=0.5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-file)    log_file="${2-}"; shift 2 ;;
    -p|--pattern)  pattern="${2-}"; shift 2 ;;
    -F|--fixed)    grep_flag="-F"; shift ;;
    -T|--timeout)  timeout="${2-}"; shift 2 ;;
    -i|--interval) interval="${2-}"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$log_file" ]]; then
  echo "log-file is required" >&2
  usage
  exit 1
fi

if ! [[ "$timeout" =~ ^[0-9]+$ ]]; then
  echo "timeout must be an integer number of seconds" >&2
  exit 1
fi

# End time in epoch seconds
start_epoch=$(date +%s)
deadline=$((start_epoch + timeout))

while true; do
  # Check if log file exists and has content
  if [[ -f "$log_file" ]]; then
    log_content="$(cat "$log_file" 2>/dev/null || true)"

    if [[ -n "$log_content" ]] && printf '%s\n' "$log_content" | grep $grep_flag -- "$pattern" >/dev/null 2>&1; then
      exit 0
    fi
  fi

  now=$(date +%s)
  if (( now >= deadline )); then
    echo "Timed out after ${timeout}s waiting for pattern: $pattern" >&2
    if [[ -f "$log_file" ]]; then
      echo "Last content from $log_file:" >&2
      tail -n 50 "$log_file" >&2 || true
    else
      echo "Log file not found: $log_file" >&2
    fi
    exit 1
  fi

  sleep "$interval"
done
