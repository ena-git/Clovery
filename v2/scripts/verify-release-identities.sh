#!/bin/sh

set -eu

v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
ios_project="$v2_root/apps/mobile/ios/Runner.xcodeproj/project.pbxproj"
ios_entitlements="$v2_root/apps/mobile/ios/Runner/Runner.entitlements"
android_gradle="$v2_root/apps/mobile/android/app/build.gradle.kts"
android_activity="$v2_root/apps/mobile/android/app/src/main/kotlin/com/clovery/app/MainActivity.kt"

require_text() {
  file_path=$1
  expected_text=$2
  failure_message=$3

  if ! grep -Fq "$expected_text" "$file_path"; then
    echo "release identity check failed: $failure_message" >&2
    exit 1
  fi
}

reject_text() {
  file_path=$1
  rejected_text=$2
  failure_message=$3

  if grep -Fq "$rejected_text" "$file_path"; then
    echo "release identity check failed: $failure_message" >&2
    exit 1
  fi
}

require_text "$ios_project" "PRODUCT_BUNDLE_IDENTIFIER = com.clovery.app;" "iOS bundle ID must preserve the App Store listing"
require_text "$ios_project" "DEVELOPMENT_TEAM = M92TBSSR2R;" "iOS development team must preserve the App Store signing owner"
require_text "$ios_project" "CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;" "iOS entitlements must be attached to Runner"
require_text "$ios_project" "IPHONEOS_DEPLOYMENT_TARGET = 17.0;" "iOS deployment target must be 17.0"
reject_text "$ios_project" "com.clovery.mobile" "generated placeholder iOS identifier is forbidden"

require_text "$ios_entitlements" "iCloud.com.clovery.app" "V1 iCloud container must remain available during migration"
require_text "$ios_entitlements" "group.com.clovery.app" "existing App Group must remain available"
require_text "$ios_entitlements" '$(TeamIdentifierPrefix)com.clovery.app' "existing iCloud KVS identifier must remain available"
require_text "$ios_entitlements" "com.apple.developer.applesignin" "Sign in with Apple entitlement is required"

require_text "$android_gradle" 'namespace = "com.clovery.app"' "Android namespace must use the first-release identity"
require_text "$android_gradle" 'applicationId = "com.clovery.app"' "Android application ID must use the first-release identity"
require_text "$android_gradle" 'signingConfigs.getByName("release")' "Android release must use the protected release signing config"
reject_text "$android_gradle" 'signingConfigs.getByName("debug")' "Android release must never use the debug key"
require_text "$android_activity" "package com.clovery.app" "Android activity package must match the application namespace"

echo "release identities verified"
