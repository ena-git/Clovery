#!/usr/bin/env bash
set -euo pipefail

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
source "$repository_root/scripts/lib/ios-simulator-matrix.sh"

run_ios_simulator_matrix "$repository_root"
