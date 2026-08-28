#!/usr/bin/env bash
# Write stdin atomically to ~/.local/state/elementary/<name>. The plugin's only
# write path — a half-written progress file would read back as "nothing done".
set -euo pipefail

name="$(basename -- "${1:?usage: state-store.sh <filename>}")"
dir="${XDG_STATE_HOME:-$HOME/.local/state}/elementary"

mkdir -p "$dir"
tmp="$(mktemp "$dir/.$name.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp"
chmod 0644 "$tmp"
mv -f "$tmp" "$dir/$name"
trap - EXIT
