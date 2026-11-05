#!/usr/bin/env bash
# Push .ats scene archives into zalivka.animation's saved folder.
#
# Defaults to the booted Simulator (instant local cp).
# Pass --device (or -d [device-name-or-id]) to push to a physical iPad/iPhone
# in a single devicectl call (one tunnel handshake for all files, skipping
# unmodified files automatically).
#
# Examples:
#   tools/push_scene.sh solargoons yellowbig
#   tools/push_scene.sh --device solargoons yellowbig
#   tools/push_scene.sh -d iPad /path/to/Cartoon_269.ats
set -euo pipefail

BUNDLE_ID="zalivka.animation"
SAVED_SUBDIR="Library/Application Support/at_elements/saved"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SEARCH_DIRS=(
  "."
  "$REPO_ROOT/files"
  "$REPO_ROOT/tools/out"
  "/Users/zalivka/ws/stickman2/testdata"
  "/Users/zalivka/ws/stickman2/testsuite/memtest"
  "/Users/zalivka/ws/stickman2/stickman/app/src/main/assets/demos"
)

MODE="sim"
DEVICE="${IOS_DEVICE:-iPad}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device)
      MODE="device"
      if [[ $# -gt 1 && "$2" != -* && ! -f "$2" && "$2" != *.ats ]]; then
        # Only consume $2 as a device name if it doesn't resolve to a scene file
        if [[ "$2" == "iPad" || "$2" == "iPhone" || "$2" =~ ^[0-9A-Fa-f-]{8,}$ ]]; then
          DEVICE="$2"
          shift
        fi
      fi
      shift
      ;;
    -s|--sim)
      MODE="sim"
      shift
      ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [--sim | --device [iPad|iPhone|<UDID>]] <scene-name-or-path>..." >&2
  exit 1
fi

resolve_scene() {
  local arg="$1"
  if [[ -f "$arg" ]]; then
    echo "$arg"
    return 0
  fi
  local name="${arg%.ats}.ats"
  for d in "${SEARCH_DIRS[@]}"; do
    if [[ -f "$d/$name" ]]; then
      echo "$d/$name"
      return 0
    fi
  done
  echo "Error: scene not found: '$arg' (searched: ${SEARCH_DIRS[*]})" >&2
  return 1
}

FILES=()
for arg in "$@"; do
  FILES+=("$(resolve_scene "$arg")")
done

if [[ "$MODE" == "sim" ]]; then
  CONTAINER="$(xcrun simctl get_app_container booted "$BUNDLE_ID" data)"
  DEST="$CONTAINER/$SAVED_SUBDIR"
  mkdir -p "$DEST"
  cp -v "${FILES[@]}" "$DEST/"
else
  SOURCE_ARGS=()
  for f in "${FILES[@]}"; do
    SOURCE_ARGS+=(--source "$f")
  done
  xcrun devicectl device copy to \
    --device "$DEVICE" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    "${SOURCE_ARGS[@]}" \
    --destination "$SAVED_SUBDIR"
fi
