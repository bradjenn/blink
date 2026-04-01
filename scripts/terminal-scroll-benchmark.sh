#!/usr/bin/env bash
set -euo pipefail

lines=200000
width=220
delay=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lines)
      lines="$2"
      shift 2
      ;;
    --width)
      width="$2"
      shift 2
      ;;
    --delay)
      delay="$2"
      shift 2
      ;;
    *)
      echo "usage: $0 [--lines N] [--width N] [--delay SECONDS]" >&2
      exit 1
      ;;
  esac
done

segment="abcdefghijklmnopqrstuvwxyz0123456789-=/:"
payload=""
while ((${#payload} < width)); do
  payload+="$segment"
done
payload="${payload:0:width}"

for ((i = 1; i <= lines; i++)); do
  color=$((31 + (i % 6)))
  printf '\033[%sm[%06d] scroll-benchmark %s :: width=%d line=%06d\033[0m\n' \
    "$color" "$i" "$payload" "$width" "$i"

  if [[ "$delay" != "0" ]]; then
    sleep "$delay"
  fi
done
