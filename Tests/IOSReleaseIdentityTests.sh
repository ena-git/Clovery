#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
checker="$repository_root/scripts/verify-ios-release-config.sh"
selector="$repository_root/scripts/select-ios-simulator.sh"

for executable in "$checker" "$selector"; do
  if [ ! -x "$executable" ]; then
    echo "missing executable release helper: $executable" >&2
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
