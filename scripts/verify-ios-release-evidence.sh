#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

gate_failure() {
  echo "iOS release evidence is incomplete or failing" >&2
  exit 1
}

evidence=$(mktemp) || gate_failure
trap 'rm -f "$evidence"' 0

git -C "$repository_root" show \
  HEAD:docs/release/ios-1.0.3-acceptance.md > "$evidence" 2>/dev/null || gate_failure

if ! candidate_commit=$(awk '
  function add_section(name) {
    sections[name] = 1
    section_total++
  }

  function add_label(section, label) {
    labels[label] = section
    label_total++
  }

  function has_status_word(value, normalized) {
    normalized = tolower(value)
    return normalized ~ /(^|[^[:alnum:]_])(not_run|pending|blocked|fail)([^[:alnum:]_]|$)/
  }

  function has_content(value) {
    return value ~ /[^[:space:]]/
  }

  function valid_evidence_path(value) {
    return value ~ /^[A-Za-z0-9._\/-]+$/ &&
      substr(value, 1, 1) != "/" &&
      substr(value, 1, 2) != "./" &&
      substr(value, length(value), 1) != "/" &&
      value != "." &&
      index(value, "..") == 0 &&
      index(value, "//") == 0
  }

  function valid_metadata(metadata, parts, count, time, device, os, evidence_path) {
    count = split(metadata, parts, "; ")
    if (count != 4 ||
        index(parts[1], "Time: ") != 1 ||
        index(parts[2], "Device: ") != 1 ||
        index(parts[3], "OS: ") != 1 ||
        index(parts[4], "Evidence: ") != 1) {
      return 0
    }

    time = substr(parts[1], length("Time: ") + 1)
    device = substr(parts[2], length("Device: ") + 1)
    os = substr(parts[3], length("OS: ") + 1)
    evidence_path = substr(parts[4], length("Evidence: ") + 1)

    return has_content(time) && !has_status_word(time) &&
      has_content(device) && !has_status_word(device) &&
      has_content(os) && !has_status_word(os) &&
      valid_evidence_path(evidence_path)
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

  {
    context = $0
    sub(/^[[:space:]]*/, "", context)
    if (substr(context, 1, 3) == "```" ||
        substr(context, 1, 3) == "~~~" ||
        index($0, "<!--") != 0 ||
        index($0, "-->") != 0 ||
        $0 ~ /^[[:space:]]+# / ||
        $0 ~ /^[[:space:]]+## /) {
      invalid = 1
    }
  }

  /^# / {
    h1_count++
    if ($0 != "# Clovery iOS 1.0.3 Acceptance Evidence") {
      invalid = 1
    }
    next
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
    next
  }

  {
    if (has_status_word($0)) {
      invalid = 1
    }
  }

  END {
    if (h1_count != 1) {
      invalid = 1
    }
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

archive="$repository_root/build/Clovery-1.0.3-14.xcarchive"
archive_info="$archive/Info.plist"
app="$archive/Products/Applications/Clovery.app"
app_info="$app/Info.plist"
widget="$app/PlugIns/CloveryWidgetExtension.appex"
widget_info="$widget/Info.plist"

[ -f "$archive_info" ] || gate_failure
[ -d "$app" ] || gate_failure
[ -f "$app_info" ] || gate_failure
[ -d "$widget" ] || gate_failure
[ -f "$widget_info" ] || gate_failure

command -v plutil >/dev/null 2>&1 || gate_failure
command -v codesign >/dev/null 2>&1 || gate_failure

plist_value() {
  plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

[ "$(plist_value "$app_info" CFBundleShortVersionString)" = "1.0.3" ] || gate_failure
[ "$(plist_value "$app_info" CFBundleVersion)" = "14" ] || gate_failure
[ "$(plist_value "$app_info" CFBundleIdentifier)" = "com.clovery.app" ] || gate_failure
[ "$(plist_value "$widget_info" CFBundleShortVersionString)" = "1.0.3" ] || gate_failure
[ "$(plist_value "$widget_info" CFBundleVersion)" = "14" ] || gate_failure
[ "$(plist_value "$widget_info" CFBundleIdentifier)" = "com.clovery.app.CloveryWidget" ] || gate_failure

codesign --verify --strict "$widget" >/dev/null 2>&1 || gate_failure
codesign --verify --strict "$app" >/dev/null 2>&1 || gate_failure

echo "iOS 1.0.3 release evidence complete"
