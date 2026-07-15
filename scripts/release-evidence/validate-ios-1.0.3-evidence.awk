function add_exact(line) {
  expected_type[++expected_total] = "exact"
  expected_value[expected_total] = line
}

function add_commit() {
  expected_type[++expected_total] = "commit"
}

function add_checklist(label) {
  expected_type[++expected_total] = "checklist"
  expected_value[expected_total] = label
}

function has_status_word(value, normalized) {
  normalized = tolower(value)
  return normalized ~ /(^|[^[:alnum:]_])(not[ _-]?run|pending|blocked|fail(ed|ure)?)([^[:alnum:]_]|$)/
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

  return has_content(time) && index(time, ";") == 0 && !has_status_word(time) &&
    has_content(device) && index(device, ";") == 0 && !has_status_word(device) &&
    has_content(os) && index(os, ";") == 0 && !has_status_word(os) &&
    valid_evidence_path(evidence_path)
}

BEGIN {
  add_exact("# Clovery iOS 1.0.3 Acceptance Evidence")
  add_commit()
  add_exact("**Archive:** `build/Clovery-1.0.3-14.xcarchive`")
  add_exact("**TestFlight build:** `14`")

  add_exact("## Automated")
  add_checklist("Native verification script")
  add_checklist("Signed Release archive")
  add_checklist("App and widget identity inspection")

  add_exact("## Upgrade And Migration")
  add_checklist("`1.0.2 (13)` to `1.0.3 (14)` data retention")
  add_checklist("Migration counts and SHA-256")
  add_checklist("Repeated export retains both bundles")

  add_exact("## Photo Library")
  add_checklist("First authorization save")
  add_checklist("Repeated save")
  add_checklist("Denial and Settings recovery")
  add_checklist("Share remains independent")

  add_exact("## StoreKit And TestFlight")
  add_checklist("Real App Store Connect price")
  add_checklist("Cancellation")
  add_checklist("Pending approval")
  add_checklist("Successful purchase")
  add_checklist("Relaunch and reinstall restore")
  add_checklist("Second-device restore")
  add_checklist("TestFlight smoke")

  add_exact("## Privacy")
  add_exact("- Git excludes account credentials, email addresses, stable account identifiers, passwords, verification codes, and recovery codes.")
  add_exact("- Git excludes receipts, tokens, transaction payloads, transaction IDs, original transaction IDs, and raw entitlement state.")
  add_exact("- Git excludes diary content, photos, tombstones, migration ZIPs, manifests, content SHA-256 hashes, device UDIDs, and stable device identifiers.")
  add_exact("- Git records only aggregate PASS results, test time, device model, OS version, and non-sensitive evidence filenames.")
  add_exact("- Raw counts, hashes, screenshots, logs, archives, and restricted evidence remain under the gitignored `build/release-evidence/ios-1.0.3/` directory.")
}

$0 == "" {
  next
}

{
  position++
  type = expected_type[position]
  value = expected_value[position]

  if (type == "exact") {
    if ($0 != value) {
      invalid = 1
    }
    next
  }

  if (type == "commit") {
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

  if (type == "checklist") {
    prefix = "- [x] " value " — PASS — "
    if (index($0, prefix) != 1 || !valid_metadata(substr($0, length(prefix) + 1))) {
      invalid = 1
    }
    next
  }

  invalid = 1
}

END {
  if (position != expected_total || invalid) {
    exit 1
  }
  print commit
}
