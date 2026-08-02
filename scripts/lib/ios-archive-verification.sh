#!/bin/sh

cleanup_ios_archive_verification() {
  if [ -n "${archive_verification_root:-}" ] && [ -d "$archive_verification_root" ]; then
    rm -rf "$archive_verification_root"
  fi
}

archive_verification_failure() {
  echo "iOS 1.1.0 archive verification failed: $1" >&2
  exit 1
}

require_archive_value() {
  label=$1
  actual=$2
  expected=$3
  if [ "$actual" != "$expected" ]; then
    archive_verification_failure "$label mismatch"
  fi
}

plist_value() {
  plist=$1
  key=$2
  /usr/bin/plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true
}

require_plist_value() {
  plist=$1
  key=$2
  expected=$3
  label=$4
  require_archive_value "$label" "$(plist_value "$plist" "$key")" "$expected"
}

require_plist_array_value() {
  plist=$1
  key=$2
  expected=$3
  label=$4
  if ! /usr/bin/plutil -extract "$key" json -o - "$plist" 2>/dev/null \
    | grep -Fq "\"$expected\""; then
    archive_verification_failure "$label missing"
  fi
}

extract_entitlements() {
  bundle=$1
  output=$2
  log=$3
  if ! /usr/bin/codesign -d --entitlements :- "$bundle" >"$output" 2>"$log"; then
    archive_verification_failure "unable to inspect signed entitlements"
  fi
  if ! /usr/bin/plutil -lint "$output" >/dev/null; then
    archive_verification_failure "signed entitlements are not a valid property list"
  fi
}

verify_ios_archive() {
  archive_path=$1
  expected_main_bundle=com.clovery.app
  expected_widget_bundle=com.clovery.app.CloveryWidget
  expected_marketing_version=1.1.0
  expected_build_number=15
  expected_team=M92TBSSR2R
  expected_app_group=group.com.clovery.app
  expected_icloud_container=iCloud.com.clovery.app

  if [ ! -d "$archive_path" ]; then
    archive_verification_failure "archive does not exist"
  fi

  archive_verification_root=$(mktemp -d /private/tmp/clovery-ios-archive.XXXXXX)
  trap cleanup_ios_archive_verification EXIT HUP INT TERM

  app="$archive_path/Products/Applications/Clovery.app"
  widget="$app/PlugIns/CloveryWidgetExtension.appex"
  app_info="$app/Info.plist"
  widget_info="$widget/Info.plist"
  privacy_manifest="$app/PrivacyInfo.xcprivacy"

  [ -d "$app" ] || archive_verification_failure "Clovery.app is missing"
  [ -d "$widget" ] || archive_verification_failure "widget extension is missing"
  [ -f "$app_info" ] || archive_verification_failure "app Info.plist is missing"
  [ -f "$widget_info" ] || archive_verification_failure "widget Info.plist is missing"
  [ -f "$privacy_manifest" ] || archive_verification_failure "PrivacyInfo.xcprivacy is missing"

  require_plist_value "$app_info" CFBundleIdentifier "$expected_main_bundle" "main bundle ID"
  require_plist_value "$widget_info" CFBundleIdentifier "$expected_widget_bundle" "widget bundle ID"
  require_plist_value "$app_info" CFBundleShortVersionString "$expected_marketing_version" "marketing version"
  require_plist_value "$app_info" CFBundleVersion "$expected_build_number" "build number"
  require_plist_value "$widget_info" CFBundleShortVersionString "$expected_marketing_version" "widget marketing version"
  require_plist_value "$widget_info" CFBundleVersion "$expected_build_number" "widget build number"

  if find "$archive_path" -name Clovery.storekit -print -quit | grep -q .; then
    archive_verification_failure "Clovery.storekit must not be embedded in Release"
  fi

  if ! /usr/bin/codesign --verify --deep --strict "$app" \
    >"$archive_verification_root/codesign.out" 2>"$archive_verification_root/codesign.log"; then
    archive_verification_failure "code signature verification failed"
  fi

  app_entitlements="$archive_verification_root/app-entitlements.plist"
  widget_entitlements="$archive_verification_root/widget-entitlements.plist"
  extract_entitlements "$app" "$app_entitlements" "$archive_verification_root/app-entitlements.log"
  extract_entitlements "$widget" "$widget_entitlements" "$archive_verification_root/widget-entitlements.log"

  require_plist_value "$app_entitlements" application-identifier \
    "$expected_team.$expected_main_bundle" "main application identifier"
  require_plist_value "$app_entitlements" com.apple.developer.team-identifier \
    "$expected_team" "main team identifier"
  require_plist_value "$app_entitlements" aps-environment production "push environment"
  require_plist_array_value "$app_entitlements" com.apple.security.application-groups \
    "$expected_app_group" "main app group"
  require_plist_array_value "$app_entitlements" com.apple.developer.ubiquity-container-identifiers \
    "$expected_icloud_container" "iCloud container"

  require_plist_value "$widget_entitlements" application-identifier \
    "$expected_team.$expected_widget_bundle" "widget application identifier"
  require_plist_array_value "$widget_entitlements" com.apple.security.application-groups \
    "$expected_app_group" "widget app group"

  printf '%s\n' "Clovery iOS 1.1.0 signed archive verified"
  printf '%s\n' "- Release identity: PASS"
  printf '%s\n' "- Code signatures: PASS"
  printf '%s\n' "- Production entitlements: PASS"
  printf '%s\n' "- Privacy manifest: PASS"
  printf '%s\n' "- Local StoreKit configuration excluded: PASS"
  printf '%s\n' "Temporary entitlement extracts and codesign logs will be removed."
}
