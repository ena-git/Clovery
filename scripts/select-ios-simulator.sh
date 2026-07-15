#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

query_destinations() {
  xcodebuild \
    -project "$repository_root/Clovery.xcodeproj" \
    -scheme Clovery \
    -showdestinations
}

extract_available_ids() {
  awk '
  /Available destinations/ { ineligible = 0; next }
  /Ineligible destinations/ { ineligible = 1; next }
  !ineligible && /platform:iOS Simulator/ && /name:iPhone/ && !/error:/ {
    device_id = $0
    sub(/^.*id:/, "", device_id)
    sub(/,.*/, "", device_id)
    gsub(/[[:space:]]/, "", device_id)
    if (device_id != "" &&
        device_id !~ /[Pp]laceholder/ &&
        device_id !~ /^dvtdevice-/ &&
        !seen[device_id]++) {
      device_os = $0
      sub(/^.*OS:/, "", device_os)
      sub(/,.*/, "", device_os)
      gsub(/[[:space:]]/, "", device_os)
      version_count = split(device_os, version, ".")
      major = version_count >= 1 ? version[1] + 0 : 0
      minor = version_count >= 2 ? version[2] + 0 : 0
      patch = version_count >= 3 ? version[3] + 0 : 0
      score = major * 1000000 + minor * 1000 + patch

      device_count++
      device_ids[device_count] = device_id
      if (device_count == 1 || score > best_score) {
        best_score = score
        best_index = device_count
      }
    }
  }
  END {
    if (best_index > 0) {
      print device_ids[best_index]
    }
    for (device_index = 1; device_index <= device_count; device_index++) {
      if (device_index != best_index) {
        print device_ids[device_index]
      }
    }
  }
  '
}

if ! destinations=$(query_destinations); then
  echo "failed to query iOS simulator destinations" >&2
  exit 1
fi

available_ids=$(printf '%s\n' "$destinations" | extract_available_ids)

if [ -z "$available_ids" ] && command -v xcrun >/dev/null 2>&1; then
  xcrun simctl list devices available >/dev/null 2>&1 || true
  sleep 1
  if ! destinations=$(query_destinations); then
    echo "failed to query iOS simulator destinations after CoreSimulator warmup" >&2
    exit 1
  fi
  available_ids=$(printf '%s\n' "$destinations" | extract_available_ids)
fi

if [ -z "$available_ids" ]; then
  printf '%s\n' "$destinations" >&2
  echo "no available iPhone Simulator destination" >&2
  exit 1
fi

if [ -n "${CLOVERY_IOS_DESTINATION:-}" ]; then
  case "$CLOVERY_IOS_DESTINATION" in
    id=?*) requested_id=${CLOVERY_IOS_DESTINATION#id=} ;;
    *)
      echo "invalid iPhone Simulator destination override: $CLOVERY_IOS_DESTINATION" >&2
      exit 1
      ;;
  esac

  case "$requested_id" in
    *[Pp]laceholder*|dvtdevice-*)
      echo "invalid iPhone Simulator destination override: $CLOVERY_IOS_DESTINATION" >&2
      exit 1
      ;;
  esac

  override_is_available=false
  for available_id in $available_ids; do
    if [ "$requested_id" = "$available_id" ]; then
      override_is_available=true
      break
    fi
  done

  if [ "$override_is_available" != true ]; then
    echo "unavailable iPhone Simulator destination override: $CLOVERY_IOS_DESTINATION" >&2
    exit 1
  fi

  printf '%s\n' "$CLOVERY_IOS_DESTINATION"
  exit 0
fi

device_id=$(printf '%s\n' "$available_ids" | head -n 1)
printf 'id=%s\n' "$device_id"
