#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$repository_root/scripts/lib/ios-archive-verification.sh"

if [ "$#" -ne 1 ]; then
  echo "usage: $0 /path/to/Clovery-1.1.0-15.xcarchive" >&2
  exit 64
fi

verify_ios_archive "$1"
