#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
checker="$repository_root/scripts/verify-ios-release-config.sh"
selector="$repository_root/scripts/select-ios-simulator.sh"

for executable in "$checker" "$selector"; do
  if [ ! -x "$executable" ]; then
    echo "missing executable release helper: $executable" >&2
    exit 1
  fi
done

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/clovery-ios-release-identity.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

fixture_root="$temporary_directory/repository"
fixture_bin="$fixture_root/bin"
fixture_checker="$fixture_root/scripts/verify-ios-release-config.sh"
fixture_selector="$fixture_root/scripts/select-ios-simulator.sh"
probe_output="$temporary_directory/probe-output.txt"

mkdir -p \
  "$fixture_bin" \
  "$fixture_root/Clovery.xcodeproj" \
  "$fixture_root/Clovery" \
  "$fixture_root/scripts"
cp "$checker" "$fixture_checker"
cp "$selector" "$fixture_selector"
chmod +x "$fixture_checker" "$fixture_selector"
printf '%s\n' 'INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription' > "$fixture_root/Clovery.xcodeproj/project.pbxproj"

cat > "$fixture_bin/xcodebuild" <<'EOF'
#!/bin/sh
set -eu

target=
show_destinations=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    -target)
      shift
      target=$1
      ;;
    -showdestinations)
      show_destinations=true
      ;;
  esac
  shift
done

if [ "$show_destinations" = true ]; then
  if [ "${NO_IPHONE_SIMULATOR:-}" = 1 ]; then
    cat <<'DESTINATIONS'
Available destinations for the "Clovery" scheme:
    { platform:macOS, arch:arm64, id:MAC-AVAILABLE-ID, name:My Mac }
    { platform:iOS Simulator, arch:arm64, id:IPAD-AVAILABLE-ID, OS:26.0, name:iPad Pro 13-inch }
    { platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }
DESTINATIONS
  else
    cat <<'DESTINATIONS'
Available destinations for the "Clovery" scheme:
    { platform:macOS, arch:arm64, id:MAC-AVAILABLE-ID, name:My Mac }
    { platform:iOS Simulator, arch:arm64, id:IPHONE-AVAILABLE-ID, OS:26.0, name:iPhone 17 Pro }
    { platform:iOS Simulator, arch:arm64, id:IPAD-AVAILABLE-ID, OS:26.0, name:iPad Pro 13-inch }
    { platform:iOS Simulator, id:dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder, name:Any iOS Simulator Device }
Ineligible destinations for the "Clovery" scheme:
    { platform:iOS Simulator, arch:arm64, id:IPHONE-INELIGIBLE-ID, OS:18.0, name:iPhone 15, error:iOS 18.0 is not installed }
DESTINATIONS
  fi
  exit 0
fi

case "$target" in
  Clovery)
    cat <<SETTINGS
Build settings for action build and target Clovery:
    MARKETING_VERSION = 1.0.3
    CURRENT_PROJECT_VERSION = 14
    PRODUCT_BUNDLE_IDENTIFIER = com.clovery.app
    CLOVERY_SOURCE_COMMIT = ${APP_SOURCE_COMMIT-NOT_SET}
    INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = ${APP_PHOTO_USAGE-Clovery saves your lucky moment cards to Photos.}
    CODE_SIGN_ENTITLEMENTS = ${APP_CODE_SIGN_ENTITLEMENTS-Clovery/Clovery.entitlements}
SETTINGS
    ;;
  CloveryWidgetExtension)
    cat <<SETTINGS
Build settings for action build and target CloveryWidgetExtension:
    MARKETING_VERSION = 1.0.3
    CURRENT_PROJECT_VERSION = 14
    PRODUCT_BUNDLE_IDENTIFIER = com.clovery.app.CloveryWidget
    CODE_SIGN_ENTITLEMENTS = ${WIDGET_CODE_SIGN_ENTITLEMENTS-CloveryWidgetExtension.entitlements}
SETTINGS
    ;;
  *)
    echo "unexpected fake xcodebuild target: $target" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$fixture_bin/xcodebuild"

write_app_entitlements() {
  app_group_key=$1
  app_group_value=$2
  icloud_key=$3
  icloud_value=$4
  cat > "$fixture_root/Clovery/Clovery.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>$app_group_key</key>
  <array>
    <string>$app_group_value</string>
  </array>
  <key>$icloud_key</key>
  <array>
    <string>$icloud_value</string>
  </array>
</dict>
</plist>
EOF
}

write_widget_entitlements() {
  app_group_key=$1
  app_group_value=$2
  cat > "$fixture_root/CloveryWidgetExtension.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>$app_group_key</key>
  <array>
    <string>$app_group_value</string>
  </array>
</dict>
</plist>
EOF
}

reset_entitlements() {
  write_app_entitlements \
    com.apple.security.application-groups \
    group.com.clovery.app \
    com.apple.developer.icloud-container-identifiers \
    iCloud.com.clovery.app
  write_widget_entitlements \
    com.apple.security.application-groups \
    group.com.clovery.app
}

write_app_info() {
  source_commit_value=$1
  cat > "$fixture_root/Clovery/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CloverySourceCommit</key>
  <string>$source_commit_value</string>
</dict>
</plist>
EOF
}

expect_failure() {
  label=$1
  shift
  if "$@" > "$probe_output" 2>&1; then
    echo "negative probe unexpectedly passed: $label" >&2
    cat "$probe_output" >&2
    exit 1
  fi
}

expect_success() {
  label=$1
  shift
  if ! "$@" > "$probe_output" 2>&1; then
    echo "positive probe failed: $label" >&2
    cat "$probe_output" >&2
    exit 1
  fi
}

reset_entitlements
write_app_info '$(CLOVERY_SOURCE_COMMIT)'
expect_failure "empty photo-library usage description" \
  env PATH="$fixture_bin:$PATH" APP_PHOTO_USAGE= "$fixture_checker"
expect_failure "wrong source commit build default" \
  env PATH="$fixture_bin:$PATH" APP_SOURCE_COMMIT=WRONG "$fixture_checker"
write_app_info 'WRONG'
expect_failure "wrong source commit Info placeholder" \
  env PATH="$fixture_bin:$PATH" "$fixture_checker"
write_app_info '$(CLOVERY_SOURCE_COMMIT)'
expect_failure "mismatched app CODE_SIGN_ENTITLEMENTS" \
  env PATH="$fixture_bin:$PATH" APP_CODE_SIGN_ENTITLEMENTS=Wrong/App.entitlements "$fixture_checker"
expect_failure "mismatched widget CODE_SIGN_ENTITLEMENTS" \
  env PATH="$fixture_bin:$PATH" WIDGET_CODE_SIGN_ENTITLEMENTS=Wrong/Widget.entitlements "$fixture_checker"

write_app_entitlements \
  wrong.application-groups \
  group.com.clovery.app \
  com.apple.developer.icloud-container-identifiers \
  iCloud.com.clovery.app
expect_failure "app group under wrong plist key" env PATH="$fixture_bin:$PATH" "$fixture_checker"

write_app_entitlements \
  com.apple.security.application-groups \
  group.com.clovery.wrong \
  com.apple.developer.icloud-container-identifiers \
  iCloud.com.clovery.app
expect_failure "wrong app group value" env PATH="$fixture_bin:$PATH" "$fixture_checker"

write_app_entitlements \
  com.apple.security.application-groups \
  group.com.clovery.app \
  wrong.icloud-container-identifiers \
  iCloud.com.clovery.app
expect_failure "iCloud container under wrong plist key" env PATH="$fixture_bin:$PATH" "$fixture_checker"

write_app_entitlements \
  com.apple.security.application-groups \
  group.com.clovery.app \
  com.apple.developer.icloud-container-identifiers \
  iCloud.com.clovery.wrong
expect_failure "wrong iCloud container value" env PATH="$fixture_bin:$PATH" "$fixture_checker"

reset_entitlements
write_widget_entitlements wrong.application-groups group.com.clovery.app
expect_failure "widget group under wrong plist key" env PATH="$fixture_bin:$PATH" "$fixture_checker"

write_widget_entitlements com.apple.security.application-groups group.com.clovery.wrong
expect_failure "wrong widget group value" env PATH="$fixture_bin:$PATH" "$fixture_checker"

reset_entitlements
/usr/libexec/PlistBuddy \
  -c 'Add :com.apple.security.application-groups:1 string group.com.clovery.extra' \
  "$fixture_root/Clovery/Clovery.entitlements"
expect_failure "additional app group value" env PATH="$fixture_bin:$PATH" "$fixture_checker"

reset_entitlements
/usr/libexec/PlistBuddy \
  -c 'Add :com.apple.developer.icloud-container-identifiers:1 string iCloud.com.clovery.extra' \
  "$fixture_root/Clovery/Clovery.entitlements"
expect_failure "additional iCloud container value" env PATH="$fixture_bin:$PATH" "$fixture_checker"

reset_entitlements
/usr/libexec/PlistBuddy \
  -c 'Add :com.apple.security.application-groups:1 string group.com.clovery.extra' \
  "$fixture_root/CloveryWidgetExtension.entitlements"
expect_failure "additional widget group value" env PATH="$fixture_bin:$PATH" "$fixture_checker"

reset_entitlements
expect_success "exact release identity fixture" env PATH="$fixture_bin:$PATH" "$fixture_checker"

discovered_destination=$(PATH="$fixture_bin:$PATH" "$fixture_selector")
if [ "$discovered_destination" != "id=IPHONE-AVAILABLE-ID" ]; then
  echo "selector did not discover the first available iPhone: $discovered_destination" >&2
  exit 1
fi

validated_destination=$(CLOVERY_IOS_DESTINATION="$discovered_destination" PATH="$fixture_bin:$PATH" "$fixture_selector")
if [ "$validated_destination" != "$discovered_destination" ]; then
  echo "selector changed a valid override: $validated_destination" >&2
  exit 1
fi

for invalid_destination in \
  'id=' \
  'id=dvtdevice-DVTiOSDeviceSimulatorPlaceholder-iphonesimulator:placeholder' \
  'id=IPAD-AVAILABLE-ID' \
  'id=MAC-AVAILABLE-ID' \
  'id=IPHONE-INELIGIBLE-ID' \
  'platform=iOS Simulator' \
  'id=UNKNOWN-NON-IPHONE-ID'
do
  expect_failure "invalid simulator override $invalid_destination" \
    env PATH="$fixture_bin:$PATH" CLOVERY_IOS_DESTINATION="$invalid_destination" "$fixture_selector"
done

expect_failure "no available iPhone simulator" \
  env PATH="$fixture_bin:$PATH" NO_IPHONE_SIMULATOR=1 "$fixture_selector"
if ! grep -Fq 'no available iPhone Simulator destination' "$probe_output"; then
  echo "missing visible no-simulator failure" >&2
  cat "$probe_output" >&2
  exit 1
fi

echo "iOS release identity negative probes verified"
