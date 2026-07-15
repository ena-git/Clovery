#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
evidence="$repository_root/docs/release/ios-1.0.3-acceptance.md"

if grep -Eq '\[ \]|NOT_RUN|FAIL|BLOCKED' "$evidence"; then
  echo "iOS release evidence is incomplete or failing" >&2
  exit 1
fi

for section in Automated "Upgrade And Migration" "Photo Library" "StoreKit And TestFlight" Privacy; do
  grep -Fq "## $section" "$evidence"
done

echo "iOS 1.0.3 release evidence complete"
