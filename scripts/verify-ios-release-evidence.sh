#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
default_evidence="$repository_root/docs/release/ios-1.0.3-acceptance.md"
evidence=${CLOVERY_IOS_EVIDENCE_PATH:-$default_evidence}

gate_failure() {
  echo "iOS release evidence is incomplete or failing" >&2
  exit 1
}

[ -f "$evidence" ] || gate_failure

if ! candidate_commit=$(awk '
  function add_section(name) {
    sections[name] = 1
    section_total++
  }

  function add_label(section, label) {
    labels[label] = section
    label_total++
  }

  function has_value(part, prefix, value) {
    if (index(part, prefix) != 1) {
      return 0
    }
    value = substr(part, length(prefix) + 1)
    return value ~ /[^[:space:]]/
  }

  function valid_metadata(metadata, parts, count) {
    count = split(metadata, parts, "; ")
    return count == 4 &&
      has_value(parts[1], "Time: ") &&
      has_value(parts[2], "Device: ") &&
      has_value(parts[3], "OS: ") &&
      has_value(parts[4], "Evidence: ")
  }

  BEGIN {
    add_section("Automated")
    add_section("Upgrade And Migration")
    add_section("Photo Library")
    add_section("StoreKit And TestFlight")
    add_section("Privacy")

    add_label("Automated", "Native verification script")
    add_label("Automated", "Signed Release archive")
    add_label("Automated", "App and widget identity inspection")
    add_label("Upgrade And Migration", "`1.0.2 (13)` to `1.0.3 (14)` data retention")
    add_label("Upgrade And Migration", "Migration counts and SHA-256")
    add_label("Upgrade And Migration", "Repeated export retains both bundles")
    add_label("Photo Library", "First authorization save")
    add_label("Photo Library", "Repeated save")
    add_label("Photo Library", "Denial and Settings recovery")
    add_label("Photo Library", "Share remains independent")
    add_label("StoreKit And TestFlight", "Real App Store Connect price")
    add_label("StoreKit And TestFlight", "Cancellation")
    add_label("StoreKit And TestFlight", "Pending approval")
    add_label("StoreKit And TestFlight", "Successful purchase")
    add_label("StoreKit And TestFlight", "Relaunch and reinstall restore")
    add_label("StoreKit And TestFlight", "Second-device restore")
    add_label("StoreKit And TestFlight", "TestFlight smoke")
  }

  index($0, "**Commit:**") == 1 {
    commit_count++
    prefix = "**Commit:** `"
    if (index($0, prefix) != 1 || substr($0, length($0), 1) != "`") {
      invalid = 1
      next
    }
    commit = substr($0, length(prefix) + 1, length($0) - length(prefix) - 1)
    if (length(commit) != 40 || commit ~ /[^0-9a-f]/) {
      invalid = 1
    }
    next
  }

  index($0, "**Archive:**") == 1 {
    archive_count++
    if ($0 != "**Archive:** `build/Clovery-1.0.3-14.xcarchive`") {
      invalid = 1
    }
    next
  }

  index($0, "**TestFlight build:**") == 1 {
    testflight_count++
    if ($0 != "**TestFlight build:** `14`") {
      invalid = 1
    }
    next
  }

  /^## / {
    heading = substr($0, 4)
    heading_count++
    if (!(heading in sections)) {
      invalid = 1
    } else {
      section_count[heading]++
    }
    current_section = heading
    next
  }

  /^[[:space:]]*[-+*][[:space:]]*\[[^]]*\]/ {
    checklist_count++
    matched = 0
    for (label in labels) {
      prefix = "- [x] " label " — PASS — "
      if (index($0, prefix) == 1) {
        matched++
        label_count[label]++
        if (current_section != labels[label]) {
          invalid = 1
        }
        metadata = substr($0, length(prefix) + 1)
        if (!valid_metadata(metadata)) {
          invalid = 1
        }
      }
    }
    if (matched != 1) {
      invalid = 1
    }
  }

  END {
    if (commit_count != 1 || archive_count != 1 || testflight_count != 1) {
      invalid = 1
    }
    if (heading_count != section_total || checklist_count != label_total) {
      invalid = 1
    }
    for (section in sections) {
      if (section_count[section] != 1) {
        invalid = 1
      }
    }
    for (label in labels) {
      if (label_count[label] != 1) {
        invalid = 1
      }
    }
    if (invalid) {
      exit 1
    }
    print commit
  }
' "$evidence" 2>/dev/null); then
  gate_failure
fi

release_commit=${CLOVERY_RELEASE_COMMIT:-}
[ -n "$release_commit" ] || gate_failure
[ "$candidate_commit" = "$release_commit" ] || gate_failure

git -C "$repository_root" cat-file -e "$candidate_commit^{commit}" 2>/dev/null || gate_failure
git -C "$repository_root" merge-base --is-ancestor "$candidate_commit" HEAD 2>/dev/null || gate_failure

if ! git -C "$repository_root" diff --quiet "${candidate_commit}..HEAD" -- \
  . ':(top,exclude,glob)docs/release/*.md' 2>/dev/null; then
  gate_failure
fi

[ -d "$repository_root/build/Clovery-1.0.3-14.xcarchive" ] || gate_failure

echo "iOS 1.0.3 release evidence complete"
