#!/usr/bin/env bash
# Extract one upright frame from a clip as PNG (AC-093).
# Usage: scripts/extract-frame.sh <clip.mov> <second> <out.png>
# Uses ffmpeg if present (applies the track rotation), else an AVAssetImageGenerator Swift script.
set -euo pipefail
if [[ $# -ne 3 ]]; then echo "usage: $0 <clip> <second> <out.png>" >&2; exit 2; fi
clip=$1; second=$2; out=$3

ffmpeg_bin=$(command -v ffmpeg || true)
[[ -z "$ffmpeg_bin" && -x /opt/homebrew/bin/ffmpeg ]] && ffmpeg_bin=/opt/homebrew/bin/ffmpeg

if [[ -n "$ffmpeg_bin" ]]; then
  "$ffmpeg_bin" -hide_banner -loglevel error -y -ss "$second" -i "$clip" -frames:v 1 "$out"
else
  swift "$(dirname "$0")/extract-frame.swift" "$clip" "$second" "$out"
fi
echo "$out"
