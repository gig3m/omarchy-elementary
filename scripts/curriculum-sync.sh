#!/usr/bin/env bash
# Resolve a curriculum source to a directory on disk, and print one line of
# JSON describing what happened. Never exits non-zero for an ordinary failure:
# the reader window renders the message, so a broken network must still produce
# a parseable answer.
#
#   usage: curriculum-sync.sh <source> [branch]
#
# <source> is either a path to a directory on this machine (read in place, never
# pulled — that is the authoring path) or a git URL (cloned once into the cache,
# fast-forwarded after that).

set -uo pipefail

source_arg="${1:-}"
branch="${2:-main}"
cache_root="${XDG_DATA_HOME:-$HOME/.local/share}/elementary"
cache="$cache_root/curriculum"

# JSON-safe: backslashes first, then quotes, then fold newlines and tabs.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\t'/ }"
  printf '%s' "$s"
}

emit() { # ok mode path message
  printf '{"ok":%s,"mode":"%s","path":"%s","message":"%s"}\n' \
    "$1" "$2" "$(json_escape "$3")" "$(json_escape "$4")"
  exit 0
}

if [[ -z "$source_arg" ]]; then
  emit false none "" "No curriculum source set yet."
fi

# A local directory is authoritative as-is. Someone writing lessons wants the
# file they just saved, not whatever a remote says.
if [[ -d "$source_arg" ]]; then
  resolved="$(cd "$source_arg" 2>/dev/null && pwd -P)" || \
    emit false none "" "Cannot read the folder $source_arg"
  if [[ ! -f "$resolved/course.json" ]]; then
    emit false local "$resolved" "No course.json in $resolved"
  fi
  emit true local "$resolved" "Reading lessons from $resolved"
fi

# Anything else is treated as a git URL.
if ! command -v git >/dev/null 2>&1; then
  emit false none "" "git is not installed."
fi

mkdir -p "$cache_root" 2>/dev/null || emit false none "" "Cannot create $cache_root"

if [[ -d "$cache/.git" ]]; then
  existing="$(git -C "$cache" remote get-url origin 2>/dev/null || printf '')"
  # Pointing the setting at a different repo must not fast-forward the old one
  # onto the new URL; start over instead.
  if [[ -n "$existing" && "$existing" != "$source_arg" ]]; then
    rm -rf "$cache"
  fi
fi

if [[ -d "$cache/.git" ]]; then
  err="$(git -C "$cache" pull --ff-only --quiet 2>&1)"
  if [[ $? -ne 0 ]]; then
    # A checkout that is merely stale is still perfectly readable.
    if [[ -f "$cache/course.json" ]]; then
      emit true stale "$cache" "Using the copy already downloaded (could not check for updates)"
    fi
    emit false error "$cache" "${err:-Could not update the curriculum}"
  fi
  emit true pull "$cache" "Lessons are up to date"
fi

err="$(git clone --depth 1 --branch "$branch" --quiet -- "$source_arg" "$cache" 2>&1)"
if [[ $? -ne 0 ]]; then
  rm -rf "$cache"
  emit false error "" "${err:-Could not download the curriculum}"
fi
if [[ ! -f "$cache/course.json" ]]; then
  emit false error "$cache" "That repo has no course.json at its root."
fi
emit true clone "$cache" "Downloaded the curriculum"
