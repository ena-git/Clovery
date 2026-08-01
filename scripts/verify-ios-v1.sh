#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
exec "$repository_root/scripts/verify-ios-1.1.0.sh" "$@"
