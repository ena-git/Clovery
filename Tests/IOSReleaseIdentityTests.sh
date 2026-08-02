#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
checker="$repository_root/scripts/verify-ios-release-config.sh"
selector="$repository_root/scripts/select-ios-simulator.sh"
workflow="$repository_root/.github/workflows/verify-ios-v1.yml"

for executable in "$checker" "$selector"; do
  if [ ! -x "$executable" ]; then
    echo "missing executable release helper: $executable" >&2
    exit 1
  fi
done

if ! grep -Fq \
  'DEVELOPER_DIR: /Applications/Xcode_26.0.1.app/Contents/Developer' \
  "$workflow"; then
  echo "native iOS CI must pin Xcode 26.0.1" >&2
  exit 1
fi
if grep -Eq '^[[:space:]]+paths:' "$workflow"; then
  echo "native iOS CI must validate every pull request head" >&2
  exit 1
fi
for required_step in \
  'name: Verify Clovery iOS 1.1.0 Account Upgrade' \
  'name: Verify iOS 1.1.0 account upgrade' \
  'run: scripts/verify-ios-1.1.0.sh'
do
  if ! grep -Fq "$required_step" "$workflow"; then
    echo "native iOS CI is missing required step: $required_step" >&2
    exit 1
  fi
done

"$repository_root/Tests/IOSReleaseIdentityNegativeTests.sh"
"$checker"
destination=$("$selector")
case "$destination" in
  id=?*) ;;
  *) echo "invalid simulator destination: $destination" >&2; exit 1 ;;
esac

validated_destination=$(CLOVERY_IOS_DESTINATION="$destination" "$selector")
if [ "$validated_destination" != "$destination" ]; then
  echo "simulator override validation changed destination: $validated_destination" >&2
  exit 1
fi
