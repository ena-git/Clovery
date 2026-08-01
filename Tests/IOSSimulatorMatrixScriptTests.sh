#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
entrypoint="$repository_root/scripts/verify-ios-1.1.0-simulator-matrix.sh"
implementation="$repository_root/scripts/lib/ios-simulator-matrix.sh"

require_text() {
  file=$1
  expected=$2
  label=$3
  if ! grep -Fq -- "$expected" "$file"; then
    echo "$label missing from $file" >&2
    exit 1
  fi
}

if [ ! -x "$entrypoint" ]; then
  echo "simulator matrix entrypoint must exist and be executable" >&2
  exit 1
fi
if [ ! -f "$implementation" ]; then
  echo "simulator matrix implementation must be modular" >&2
  exit 1
fi

for device_type in \
  com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation \
  com.apple.CoreSimulator.SimDeviceType.iPhone-13-mini \
  com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro \
  com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max
do
  require_text "$implementation" "$device_type" "screen-size device type"
done

require_text "$implementation" 'mktemp -d /private/tmp/clovery-ios-simulator-matrix.' "private matrix root"
require_text "$implementation" 'xcrun simctl delete' "temporary simulator cleanup"
require_text "$implementation" 'trap cleanup_simulator_matrix EXIT HUP INT TERM' "matrix cleanup trap"
require_text "$implementation" 'testAllReleaseRoutesRenderWithoutCrash' "route crash test"
require_text "$implementation" 'testAccessibilityRoutesKeepRequiredActionsReachable' "accessibility reachability test"
require_text "$implementation" 'testAccountDeletionRequiresExactCloveryID' "deletion UI test"
require_text "$implementation" 'failedTests' "XCResult failure audit"
require_text "$implementation" 'skippedTests' "XCResult skip audit"

echo "iOS simulator matrix script contract verified"
