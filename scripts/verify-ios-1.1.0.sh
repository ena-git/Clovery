#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$repository_root/scripts/lib/ios-release-verification.sh"

run_ios_release_verification "$repository_root"
