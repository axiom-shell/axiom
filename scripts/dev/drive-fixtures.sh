#!/usr/bin/env bash
# Fake removable drives for testing axiom's drive controls: image files
# set up as loop devices through UDisks2, which a scratch daemon run with
# AXIOM_DRIVES_INCLUDE_LOOP=1 shows as drives (bus "loop"). No admin
# rights: the images are built as files, and udisksctl never asks for a
# password (--no-user-interaction; a refusal is reported and skipped).
#
#   ext4.img    one ext4 filesystem, label AXEXT4
#   parts.img   a GPT disk with two ext4 partitions, AXPART1 and AXPART2
#   fat.img     one FAT32 filesystem, label AXFAT (needs mkfs.fat: dosfstools)
#   luks.img    LUKS2 holding ext4 (AXLUKS), passphrase "axiom-test"
#               (needs cryptsetup)
#
#   scripts/dev/drive-fixtures.sh images   build the images (again)
#   scripts/dev/drive-fixtures.sh up       build missing images, set each up
#   scripts/dev/drive-fixtures.sh down     unmount, lock and delete their loop devices
#   scripts/dev/drive-fixtures.sh status   list their loop devices
#   scripts/dev/drive-fixtures.sh clean    down, then delete the images
#
# The images live in $AXIOM_DRIVE_FIXTURES (default
# ~/.cache/axiom-drive-fixtures).
set -euo pipefail

dir="${AXIOM_DRIVE_FIXTURES:-${XDG_CACHE_HOME:-$HOME/.cache}/axiom-drive-fixtures}"
passphrase="axiom-test"
images=(ext4 parts fat luks)

have() { command -v "$1" >/dev/null 2>&1; }

build() {
  local name=$1 img="$dir/$1.img"
  rm -f "$img"
  case "$name" in
  ext4)
    truncate -s 32M "$img"
    mkfs.ext4 -q -L AXEXT4 "$img"
    ;;
  parts)
    truncate -s 64M "$img"
    printf 'label: gpt\nsize=24MiB, name=one\nsize=24MiB, name=two\n' | sfdisk -q "$img"
    # Each partition's filesystem written at its offset
    local start size label n=1
    while read -r start size; do
      label="AXPART$n"
      mkfs.ext4 -q -L "$label" -E offset=$((start * 512)) "$img" $((size * 512 / 1024))k
      n=$((n + 1))
    done < <(sfdisk -J "$img" | python3 -I -c 'import json, sys
for p in json.load(sys.stdin)["partitiontable"]["partitions"]: print(p["start"], p["size"])')
    ;;
  fat)
    if ! have mkfs.fat; then
      echo "skipped: fat.img (no mkfs.fat: install dosfstools)"
      return
    fi
    truncate -s 64M "$img"
    mkfs.fat -F 32 -n AXFAT "$img" >/dev/null
    ;;
  luks)
    if ! have cryptsetup; then
      echo "skipped: luks.img (no cryptsetup)"
      return
    fi
    # ext4 first, then encrypted in place: offline reencryption works on a
    # plain file, where opening the container would need device-mapper
    truncate -s 64M "$img"
    mkfs.ext4 -q -L AXLUKS "$img" 32M
    printf '%s' "$passphrase" | cryptsetup reencrypt --encrypt --type luks2 --reduce-device-size 32M \
      --disable-locks --batch-mode --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file - "$img"
    ;;
  esac
  echo "built: $img"
}

loops() { # the loop devices backed by an image
  losetup -n -O NAME -j "$1" 2>/dev/null || true
}

up() {
  mkdir -p "$dir"
  local name img
  for name in "${images[@]}"; do
    img="$dir/$name.img"
    [[ -e "$img" ]] || build "$name"
    [[ -e "$img" ]] || continue
    if [[ -n "$(loops "$img")" ]]; then
      echo "up already: $name.img on $(loops "$img" | tr '\n' ' ')"
      continue
    fi
    udisksctl loop-setup --no-user-interaction -f "$img" ||
      echo "skipped: $name.img (UDisks2 refused the loop device without asking)"
  done
}

down() {
  local name img loop dev
  for name in "${images[@]}"; do
    img="$dir/$name.img"
    [[ -e "$img" ]] || continue
    for loop in $(loops "$img"); do
      # Its partitions and any unlocked cleartext first
      for dev in $(lsblk -nrpo NAME "$loop" | tac); do
        if [[ -n "$(lsblk -nrpo MOUNTPOINTS "$dev" | head -1)" ]]; then
          udisksctl unmount --no-user-interaction -b "$dev" || true
        fi
        if [[ "$(lsblk -nrdo FSTYPE "$dev")" == crypto_LUKS && -n "$(lsblk -nrpo NAME "$dev" | sed -n 2p)" ]]; then
          udisksctl lock --no-user-interaction -b "$dev" || true
        fi
      done
      udisksctl loop-delete --no-user-interaction -b "$loop" && echo "deleted: $loop ($name.img)"
    done
  done
}

case "${1:-}" in
images)
  mkdir -p "$dir"
  for name in "${images[@]}"; do build "$name"; done
  ;;
up) up ;;
down) down ;;
status)
  for name in "${images[@]}"; do
    [[ -e "$dir/$name.img" ]] && echo "$name.img: $(loops "$dir/$name.img" | tr '\n' ' ')"
  done
  ;;
clean)
  down
  rm -rf "$dir"
  ;;
*) sed -n '2,22p' "$0" >&2; exit 2 ;;
esac
