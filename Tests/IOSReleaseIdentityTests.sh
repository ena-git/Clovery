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

"$checker"
destination=$("$selector")
case "$destination" in
  id=*|platform=*) ;;
  *) echo "invalid simulator destination: $destination" >&2; exit 1 ;;
esac
