#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
project="$repository_root/Clovery.xcodeproj"
scheme="$project/xcshareddata/xcschemes/Clovery.xcscheme"
privacy_manifest="$repository_root/Clovery/PrivacyInfo.xcprivacy"
legal_source="$repository_root/Clovery/Features/Legal/LegalDocument.swift"

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

assert_file_contains() {
  file=$1
  expected=$2
  label=$3
  if ! grep -Fq "$expected" "$file"; then
    echo "$label missing from $file" >&2
    exit 1
  fi
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

assert_privacy_data_type() {
  index=$1
  expected_type=$2
  base=":NSPrivacyCollectedDataTypes:$index"
  assert_equal \
    "$(/usr/libexec/PlistBuddy -c "Print $base:NSPrivacyCollectedDataType" "$privacy_manifest")" \
    "$expected_type" \
    "privacy data type $index"
  assert_equal \
    "$(/usr/libexec/PlistBuddy -c "Print $base:NSPrivacyCollectedDataTypeLinked" "$privacy_manifest")" \
    true \
    "privacy linked flag $expected_type"
  assert_equal \
    "$(/usr/libexec/PlistBuddy -c "Print $base:NSPrivacyCollectedDataTypeTracking" "$privacy_manifest")" \
    false \
    "privacy tracking flag $expected_type"
  assert_plist_single_array_value \
    "$privacy_manifest" \
    "NSPrivacyCollectedDataTypes:$index:NSPrivacyCollectedDataTypePurposes" \
    NSPrivacyCollectedDataTypePurposeAppFunctionality \
    "privacy purpose $expected_type"
}

app=$(build_settings Clovery)
widget=$(build_settings CloveryWidgetExtension)

assert_equal "$(setting "$app" MARKETING_VERSION)" "1.1.0" "app marketing version"
assert_equal "$(setting "$app" CURRENT_PROJECT_VERSION)" "15" "app build number"
assert_equal "$(setting "$app" PRODUCT_BUNDLE_IDENTIFIER)" "com.clovery.app" "app bundle id"
assert_equal "$(setting "$app" CLOVERY_SOURCE_COMMIT)" "NOT_SET" "app source commit default"
assert_equal "$(setting "$app" CLOVERY_API_BASE_URL)" "https://api.clovery.cn" "production API URL"
assert_equal "$(setting "$app" CODE_SIGN_IDENTITY)" "Apple Distribution" "app Release signing identity"
assert_equal "$(setting "$app" APS_ENVIRONMENT)" "production" "app Release push environment"
assert_non_empty "$(setting "$app" INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription)" "app photo-library usage description"
assert_equal "$(setting "$app" CODE_SIGN_ENTITLEMENTS)" "Clovery/Clovery.entitlements" "app entitlements path"
assert_equal "$(setting "$widget" MARKETING_VERSION)" "1.1.0" "widget marketing version"
assert_equal "$(setting "$widget" CURRENT_PROJECT_VERSION)" "15" "widget build number"
assert_equal "$(setting "$widget" PRODUCT_BUNDLE_IDENTIFIER)" "com.clovery.app.CloveryWidget" "widget bundle id"
assert_equal "$(setting "$widget" CODE_SIGN_ENTITLEMENTS)" "CloveryWidgetExtension.entitlements" "widget entitlements path"
assert_equal "$(setting "$widget" CODE_SIGN_IDENTITY)" "Apple Distribution" "widget Release signing identity"

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
  "$repository_root/Clovery/Clovery.entitlements" \
  com.apple.developer.applesignin \
  Default \
  "Sign in with Apple entitlement"
assert_plist_single_array_value \
  "$repository_root/CloveryWidgetExtension.entitlements" \
  com.apple.security.application-groups \
  group.com.clovery.app \
  "widget group entitlement"

if ! /usr/bin/plutil -lint "$privacy_manifest" >/dev/null; then
  echo "invalid app privacy manifest" >&2
  exit 1
fi
assert_equal \
  "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyTracking' "$privacy_manifest")" \
  false \
  "privacy tracking declaration"
assert_privacy_data_type 0 NSPrivacyCollectedDataTypeUserID
assert_privacy_data_type 1 NSPrivacyCollectedDataTypeDeviceID
assert_privacy_data_type 2 NSPrivacyCollectedDataTypeOtherUserContent
assert_privacy_data_type 3 NSPrivacyCollectedDataTypePhotosorVideos
assert_privacy_data_type 4 NSPrivacyCollectedDataTypePurchaseHistory
if /usr/libexec/PlistBuddy -c 'Print :NSPrivacyCollectedDataTypes:5' "$privacy_manifest" >/dev/null 2>&1; then
  echo "privacy collected-data list contains an unreviewed extra entry" >&2
  exit 1
fi
assert_equal \
  "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPIType' "$privacy_manifest")" \
  NSPrivacyAccessedAPICategoryUserDefaults \
  "required-reason API category"
assert_equal \
  "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPITypeReasons:0' "$privacy_manifest")" \
  CA92.1 \
  "app-only UserDefaults privacy reason"
assert_equal \
  "$(/usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPITypeReasons:1' "$privacy_manifest")" \
  1C8F.1 \
  "App Group UserDefaults privacy reason"
if /usr/libexec/PlistBuddy -c 'Print :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPITypeReasons:2' "$privacy_manifest" >/dev/null 2>&1; then
  echo "UserDefaults privacy reasons contain an unreviewed extra entry" >&2
  exit 1
fi
assert_file_contains \
  "$repository_root/Clovery.xcodeproj/project.pbxproj" \
  'PrivacyInfo.xcprivacy in Resources' \
  "privacy manifest app resource"
privacy_resource_occurrences=$(grep -Fc \
  'PrivacyInfo.xcprivacy in Resources' \
  "$repository_root/Clovery.xcodeproj/project.pbxproj")
if [ "$privacy_resource_occurrences" -lt 4 ]; then
  echo "privacy manifest must be bundled by both app and widget targets" >&2
  exit 1
fi

assert_file_contains \
  "$legal_source" \
  'https://api.clovery.cn/v1/legal/privacy' \
  "production privacy URL"
assert_file_contains \
  "$legal_source" \
  'https://api.clovery.cn/v1/legal/terms' \
  "production terms URL"

release_actions=$(awk '
  /<ProfileAction/ { capture = 1 }
  capture { print }
  /<\/ArchiveAction>/ { capture = 0 }
' "$scheme")
if printf '%s\n' "$release_actions" | grep -Fq 'StoreKitConfigurationFileReference'; then
  echo "Release Profile/Archive actions must not use Clovery.storekit" >&2
  exit 1
fi

echo "iOS 1.1.0 release identity verified"
