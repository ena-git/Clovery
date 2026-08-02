#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
rules="$repository_root/scripts/lib/repository-hygiene-rules.sh"

if [ ! -f "$rules" ]; then
  echo "repository hygiene rules are missing: $rules" >&2
  exit 1
fi

. "$rules"

cd "$repository_root"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  hygiene_fail "not inside a Git worktree"
  exit 1
fi

hygiene_check_tracked_paths
hygiene_check_tracked_secret_content
hygiene_check_generated_directories "$repository_root"
hygiene_check_dirty_generated_output
hygiene_check_release_evidence

echo "repository hygiene verified"
