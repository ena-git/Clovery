#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

if [ -n "${CLOVERY_IOS_DESTINATION:-}" ]; then
  printf '%s\n' "$CLOVERY_IOS_DESTINATION"
  exit 0
fi

destinations=$(xcodebuild \
  -project "$repository_root/Clovery.xcodeproj" \
  -scheme Clovery \
  -showdestinations 2>/dev/null)

device_id=$(printf '%s\n' "$destinations" \
  | sed -n 's/.*platform:iOS Simulator,.*id:\([^,}]*\),.*name:iPhone.*/\1/p' \
  | head -n 1 \
  | tr -d ' ')

if [ -z "$device_id" ]; then
  echo "no available iPhone Simulator destination" >&2
  exit 1
fi

printf 'id=%s\n' "$device_id"
