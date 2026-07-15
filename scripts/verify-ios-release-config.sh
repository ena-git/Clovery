#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
project="$repository_root/Clovery.xcodeproj"

build_settings() {
  xcodebuild -project "$project" -target "$1" -configuration Release -showBuildSettings
}

setting() {
  printf '%s\n' "$1" | awk -F ' = ' -v key="$2" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }'
}

assert_equal() {
  actual=$1
  expected=$2
  label=$3
  if [ "$actual" != "$expected" ]; then
    echo "$label mismatch: expected $expected, got $actual" >&2
    exit 1
  fi
}

assert_non_empty() {
  value=$1
  label=$2
  case "$value" in
    *[![:space:]]*) ;;
    *)
      echo "$label must be non-empty" >&2
      exit 1
      ;;
  esac
}

assert_plist_single_array_value() {
  plist=$1
  key=$2
  expected=$3
  label=$4

  if ! actual=$(/usr/libexec/PlistBuddy -c "Print :$key:0" "$plist" 2>/dev/null); then
    echo "$label missing from $plist" >&2
    exit 1
  fi
  assert_equal "$actual" "$expected" "$label"

  if /usr/libexec/PlistBuddy -c "Print :$key:1" "$plist" >/dev/null 2>&1; then
    echo "$label mismatch: expected one value, found additional values" >&2
    exit 1
  fi
}

app=$(build_settings Clovery)
widget=$(build_settings CloveryWidgetExtension)

assert_equal "$(setting "$app" MARKETING_VERSION)" "1.0.3" "app marketing version"
assert_equal "$(setting "$app" CURRENT_PROJECT_VERSION)" "14" "app build number"
assert_equal "$(setting "$app" PRODUCT_BUNDLE_IDENTIFIER)" "com.clovery.app" "app bundle id"
assert_equal "$(setting "$app" CLOVERY_SOURCE_COMMIT)" "NOT_SET" "app source commit default"
assert_non_empty "$(setting "$app" INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription)" "app photo-library usage description"
assert_equal "$(setting "$app" CODE_SIGN_ENTITLEMENTS)" "Clovery/Clovery.entitlements" "app entitlements path"
assert_equal "$(setting "$widget" MARKETING_VERSION)" "1.0.3" "widget marketing version"
assert_equal "$(setting "$widget" CURRENT_PROJECT_VERSION)" "14" "widget build number"
assert_equal "$(setting "$widget" PRODUCT_BUNDLE_IDENTIFIER)" "com.clovery.app.CloveryWidget" "widget bundle id"
assert_equal "$(setting "$widget" CODE_SIGN_ENTITLEMENTS)" "CloveryWidgetExtension.entitlements" "widget entitlements path"

assert_equal \
  "$(/usr/libexec/PlistBuddy -c 'Print :CloverySourceCommit' "$repository_root/Clovery/Info.plist")" \
  '$(CLOVERY_SOURCE_COMMIT)' \
  "app source commit Info placeholder"

assert_plist_single_array_value \
  "$repository_root/Clovery/Clovery.entitlements" \
  com.apple.security.application-groups \
  group.com.clovery.app \
  "app group entitlement"
assert_plist_single_array_value \
  "$repository_root/Clovery/Clovery.entitlements" \
  com.apple.developer.icloud-container-identifiers \
  iCloud.com.clovery.app \
  "app iCloud container entitlement"
assert_plist_single_array_value \
  "$repository_root/CloveryWidgetExtension.entitlements" \
  com.apple.security.application-groups \
  group.com.clovery.app \
  "widget group entitlement"

echo "iOS 1.0.3 release identity verified"
