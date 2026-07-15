#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
web_view="$repository_root/Clovery/WebView.swift"
photo_library_saver="$repository_root/Clovery/PhotoLibrarySaver.swift"
board_store="$repository_root/Clovery/BoardStore.swift"
html="$repository_root/Clovery/Clover Diary.html"
project="$repository_root/Clovery.xcodeproj/project.pbxproj"
app_info_plist="$repository_root/Clovery/Info.plist"
app_entitlements="$repository_root/Clovery/Clovery.entitlements"
widget_entitlements="$repository_root/CloveryWidgetExtension.entitlements"
v2_entitlements="$repository_root/v2/apps/mobile/ios/Runner/Runner.entitlements"

require_text() {
  file_path=$1
  expected_text=$2

  if ! grep -Fq "$expected_text" "$file_path"; then
    echo "missing P0 contract: $expected_text" >&2
    exit 1
  fi
}

reject_text() {
  file_path=$1
  rejected_text=$2

  if grep -Fq "$rejected_text" "$file_path"; then
    echo "forbidden P0 regression: $rejected_text" >&2
    exit 1
  fi
}

reject_text "$web_view" '\\('
reject_text "$web_view" "UIImageWriteToSavedPhotosAlbum"
reject_text "$web_view" "PHPhotoLibrary.shared().performChanges"
require_text "$web_view" 'config.userContentController.add(context.coordinator, name: "openAppSettings")'
require_text "$web_view" "BridgeJavaScript.photoSaveResult(outcome)"
require_text "$photo_library_saver" "PHAssetCreationRequest.forAsset()"

require_text "$board_store" "func purchase() async -> BoardPurchaseOutcome"
require_text "$board_store" "com.clovery.app.board.lifetime"
require_text "$board_store" "case .userCancelled:"
require_text "$board_store" "case .pending:"
require_text "$board_store" "Transaction.updates"
reject_text "$board_store" "isTestFlight"

require_text "$html" "window.__clovery_imageSaveResult = (outcome) =>"
require_text "$html" "saveError==='permissionDenied'"
require_text "$html" "messageHandlers?.openAppSettings?.postMessage"
reject_text "$html" "window.__clovery_imageSaved"

require_text "$project" "INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription"
require_text "$project" "INFOPLIST_FILE = Clovery/Info.plist;"
reject_text "$project" "INFOPLIST_KEY_UIBackgroundModes"
reject_text "$project" "CURRENT_PROJECT_VERSION = 11;"

if [ ! -f "$app_info_plist" ]; then
  echo "missing P0 contract: Clovery/Info.plist" >&2
  exit 1
fi

background_mode=$(plutil -extract UIBackgroundModes.0 raw -o - "$app_info_plist")
if [ "$background_mode" != "remote-notification" ]; then
  echo "missing P0 contract: UIBackgroundModes remote-notification" >&2
  exit 1
fi

for entitlements in "$app_entitlements" "$widget_entitlements" "$v2_entitlements"; do
  require_text "$entitlements" "com.apple.security.application-groups"
  require_text "$entitlements" "group.com.clovery.app"
  reject_text "$entitlements" "com.apple.developer.app-groups"
done

echo "V1 photo and purchase bridge contract verified"
