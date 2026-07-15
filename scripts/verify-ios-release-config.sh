#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
project="$repository_root/Clovery.xcodeproj"

build_settings() {
  xcodebuild -project "$project" -target "$1" -configuration Release -showBuildSettings 2>/dev/null
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

app=$(build_settings Clovery)
widget=$(build_settings CloveryWidgetExtension)

assert_equal "$(setting "$app" MARKETING_VERSION)" "1.0.3" "app marketing version"
assert_equal "$(setting "$app" CURRENT_PROJECT_VERSION)" "14" "app build number"
assert_equal "$(setting "$app" PRODUCT_BUNDLE_IDENTIFIER)" "com.clovery.app" "app bundle id"
assert_equal "$(setting "$widget" MARKETING_VERSION)" "1.0.3" "widget marketing version"
assert_equal "$(setting "$widget" CURRENT_PROJECT_VERSION)" "14" "widget build number"
assert_equal "$(setting "$widget" PRODUCT_BUNDLE_IDENTIFIER)" "com.clovery.app.CloveryWidget" "widget bundle id"

grep -Fq 'INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription' "$project/project.pbxproj"
grep -Fq 'group.com.clovery.app' "$repository_root/Clovery/Clovery.entitlements"
grep -Fq 'iCloud.com.clovery.app' "$repository_root/Clovery/Clovery.entitlements"
grep -Fq 'group.com.clovery.app' "$repository_root/CloveryWidgetExtension.entitlements"

echo "iOS 1.0.3 release identity verified"
