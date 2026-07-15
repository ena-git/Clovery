#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
support_directory="$repository_root/scripts/release-evidence"
release_archive="$repository_root/build/Clovery-1.0.3-14.xcarchive"

gate_failure() {
  echo "iOS release evidence is incomplete or failing" >&2
  exit 1
}

temporary_directory=$(mktemp -d) || gate_failure
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
evidence="$temporary_directory/acceptance.md"
commits="$temporary_directory/commits.txt"
paths="$temporary_directory/paths.txt"

/usr/bin/git -C "$repository_root" show \
  HEAD:docs/release/ios-1.0.3-acceptance.md > "$evidence" 2>/dev/null || gate_failure

candidate_commit=$(/usr/bin/awk \
  -f "$support_directory/validate-ios-1.0.3-evidence.awk" \
  "$evidence" 2>/dev/null) || gate_failure
release_commit=${CLOVERY_RELEASE_COMMIT:-}

[ -n "$release_commit" ] || gate_failure
[ "$candidate_commit" = "$release_commit" ] || gate_failure

/usr/bin/git -C "$repository_root" cat-file -e "$candidate_commit^{commit}" 2>/dev/null || gate_failure
/usr/bin/git -C "$repository_root" merge-base --is-ancestor "$candidate_commit" HEAD 2>/dev/null || gate_failure

verify_evidence_only_history() {
  /usr/bin/git -C "$repository_root" rev-list \
    --reverse "${candidate_commit}..HEAD" > "$commits" 2>/dev/null || return 1

  while IFS= read -r commit; do
    parent=$(/usr/bin/git -C "$repository_root" rev-parse "$commit^1" 2>/dev/null) || return 1
    /usr/bin/git -C "$repository_root" diff-tree \
      --no-commit-id --name-only -r "$parent" "$commit" > "$paths" 2>/dev/null || return 1

    while IFS= read -r path; do
      case "$path" in
        docs/release/*.md) ;;
        *) return 1 ;;
      esac
    done < "$paths"
  done < "$commits"
}

verify_evidence_only_history || gate_failure

if ! /usr/bin/git -C "$repository_root" diff --quiet "${candidate_commit}..HEAD" -- \
  . ':(top,exclude,glob)docs/release/*.md' 2>/dev/null; then
  gate_failure
fi

/bin/sh "$support_directory/verify-ios-1.0.3-archive.sh" \
  "$release_archive" "$candidate_commit" || gate_failure

echo "iOS 1.0.3 release evidence complete"
