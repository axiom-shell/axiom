#!/usr/bin/env bash
#
# Author:      travmonkey
# Date:        2025-09-30
# Description: Sets a wallpaper with a random transition on a monitor.
# Usage:       setWallpaper.sh <path_to_image> [monitor]
#              without a monitor, every one

set -euo pipefail

if [ -z "${1:-}" ] || [ ! -f "$1" ]; then
  echo "Usage: $0 <path_to_image>"
  echo "Error: Please provide a valid path to a wallpaper image."
  exit 1
fi

WALLPAPER_PATH="$1"

awww query >/dev/null || awww init

transitions=("wipe" "any" "outer" "wave")
TRANSITION_TYPE=${transitions[$RANDOM % ${#transitions[@]}]}
awww_PARAMS="--transition-fps 144 --transition-type $TRANSITION_TYPE --transition-duration 1"

outputs=()
if [[ -n "${2:-}" ]]; then
  outputs=(-o "$2")
fi
awww img "${outputs[@]}" "$WALLPAPER_PATH" $awww_PARAMS
