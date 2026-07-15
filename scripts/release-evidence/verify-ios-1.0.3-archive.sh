#!/bin/sh
set -eu

release_archive=$1
candidate_commit=$2
release_team="M92TBSSR2R"

archive_failure() {
  exit 1
}

temporary_directory=$(mktemp -d) || archive_failure
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
app_entitlements="$temporary_directory/app-entitlements.plist"
widget_entitlements="$temporary_directory/widget-entitlements.plist"

archive_info="$release_archive/Info.plist"
app="$release_archive/Products/Applications/Clovery.app"
app_info="$app/Info.plist"
widget="$app/PlugIns/CloveryWidgetExtension.appex"
widget_info="$widget/Info.plist"

[ -f "$archive_info" ] || archive_failure
[ -d "$app" ] || archive_failure
[ -f "$app_info" ] || archive_failure
[ -d "$widget" ] || archive_failure
[ -f "$widget_info" ] || archive_failure

[ -x /usr/bin/plutil ] || archive_failure
[ -x /usr/libexec/PlistBuddy ] || archive_failure
[ -x /usr/bin/codesign ] || archive_failure
[ -x /usr/bin/file ] || archive_failure
[ -x /usr/bin/lipo ] || archive_failure

plist_value() {
  /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null
}

plist_array_values() {
  output=$(/usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null) || return 1
  printf '%s\n' "$output" | /usr/bin/awk '
    NR == 1 {
      if ($0 !~ /^[[:space:]]*Array \{[[:space:]]*$/) {
        exit 1
      }
      next
    }
    /^[[:space:]]*}[[:space:]]*$/ {
      closed++
      next
    }
    {
      value = $0
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      if (value == "" || closed) {
        exit 1
      }
      print value
    }
    END {
      if (closed != 1) {
        exit 1
      }
    }
  '
}

team_identifier() {
  /usr/bin/codesign -dv --verbose=4 "$1" 2>&1 | /usr/bin/awk -F= '
    $1 == "TeamIdentifier" {
      print substr($0, index($0, "=") + 1)
    }
  '
}

verify_arm64_macho() {
  executable=$1
  [ -f "$executable" ] || return 1
  [ ! -L "$executable" ] || return 1
  [ -x "$executable" ] || return 1

  case "$(/usr/bin/file -b "$executable" 2>/dev/null)" in
    Mach-O*executable*) ;;
    *) return 1 ;;
  esac

  /usr/bin/lipo -archs "$executable" 2>/dev/null | \
    /usr/bin/grep -Eq '(^|[[:space:]])arm64($|[[:space:]])'
}

archive_architectures=$(plist_array_values "$archive_info" "ApplicationProperties:Architectures") || archive_failure
printf '%s\n' "$archive_architectures" | /usr/bin/grep -Fxq "arm64" || archive_failure

[ "$(plist_value "$archive_info" ApplicationProperties.ApplicationPath)" = "Applications/Clovery.app" ] || archive_failure
[ "$(plist_value "$archive_info" ApplicationProperties.CFBundleIdentifier)" = "com.clovery.app" ] || archive_failure
[ "$(plist_value "$archive_info" ApplicationProperties.CFBundleShortVersionString)" = "1.0.3" ] || archive_failure
[ "$(plist_value "$archive_info" ApplicationProperties.CFBundleVersion)" = "14" ] || archive_failure
archive_signing_identity=$(plist_value "$archive_info" ApplicationProperties.SigningIdentity) || archive_failure
[ -n "$archive_signing_identity" ] || archive_failure
[ "$archive_signing_identity" != "-" ] || archive_failure

[ "$(plist_value "$app_info" CFBundleShortVersionString)" = "1.0.3" ] || archive_failure
[ "$(plist_value "$app_info" CFBundleVersion)" = "14" ] || archive_failure
[ "$(plist_value "$app_info" CFBundleIdentifier)" = "com.clovery.app" ] || archive_failure
[ "$(plist_value "$app_info" DTPlatformName)" = "iphoneos" ] || archive_failure
case "$(plist_value "$app_info" DTSDKName)" in
  iphoneos*) ;;
  *) archive_failure ;;
esac
[ "$(plist_value "$app_info" CloverySourceCommit)" = "$candidate_commit" ] || archive_failure
app_executable=$(plist_value "$app_info" CFBundleExecutable) || archive_failure
[ -n "$app_executable" ] || archive_failure
verify_arm64_macho "$app/$app_executable" || archive_failure

[ "$(plist_value "$widget_info" CFBundleShortVersionString)" = "1.0.3" ] || archive_failure
[ "$(plist_value "$widget_info" CFBundleVersion)" = "14" ] || archive_failure
[ "$(plist_value "$widget_info" CFBundleIdentifier)" = "com.clovery.app.CloveryWidget" ] || archive_failure
[ "$(plist_value "$widget_info" DTPlatformName)" = "iphoneos" ] || archive_failure
case "$(plist_value "$widget_info" DTSDKName)" in
  iphoneos*) ;;
  *) archive_failure ;;
esac
widget_executable=$(plist_value "$widget_info" CFBundleExecutable) || archive_failure
[ -n "$widget_executable" ] || archive_failure
verify_arm64_macho "$widget/$widget_executable" || archive_failure

/usr/bin/codesign --verify --strict "$widget" >/dev/null 2>&1 || archive_failure
/usr/bin/codesign --verify --strict "$app" >/dev/null 2>&1 || archive_failure
[ "$(team_identifier "$app")" = "$release_team" ] || archive_failure
[ "$(team_identifier "$widget")" = "$release_team" ] || archive_failure

/usr/bin/codesign -d --entitlements :- "$app" > "$app_entitlements" 2>/dev/null || archive_failure
/usr/bin/codesign -d --entitlements :- "$widget" > "$widget_entitlements" 2>/dev/null || archive_failure
/usr/bin/plutil -lint "$app_entitlements" >/dev/null 2>&1 || archive_failure
/usr/bin/plutil -lint "$widget_entitlements" >/dev/null 2>&1 || archive_failure

[ "$(plist_array_values "$app_entitlements" com.apple.security.application-groups)" = "group.com.clovery.app" ] || archive_failure
[ "$(plist_array_values "$app_entitlements" com.apple.developer.icloud-container-identifiers)" = "iCloud.com.clovery.app" ] || archive_failure
[ "$(plist_array_values "$widget_entitlements" com.apple.security.application-groups)" = "group.com.clovery.app" ] || archive_failure
