#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
web_view="$repository_root/Clovery/WebView.swift"
bridge_javascript="$repository_root/Clovery/BridgeJavaScript.swift"
app_source="$repository_root/Clovery/CloveryApp.swift"
photo_library_saver="$repository_root/Clovery/PhotoLibrarySaver.swift"
board_store="$repository_root/Clovery/BoardStore.swift"
board_store_client="$repository_root/Clovery/BoardStoreClient.swift"
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
require_text "$web_view" 'message.name == "openAppSettings"'
require_text "$web_view" "handleOpenAppSettings()"
require_text "$web_view" "BridgeJavaScript.photoSaveResult(outcome)"
require_text "$web_view" "private var boardEntitlementCancellable: AnyCancellable?"
require_text "$web_view" "startObservingBoardStore()"
require_text "$web_view" ".removeDuplicates()"
require_text "$web_view" ".receive(on: DispatchQueue.main)"
require_text "$web_view" "BridgeJavaScript.boardRestoreResult(outcome)"
require_text "$bridge_javascript" 'evaluateJSONCallback(name: "window._boardRestoreResult", payload: [outcome.rawValue])'
require_text "$app_source" "@Environment(\.scenePhase)"
require_text "$app_source" "WebViewCoordinatorBridge.shared.refreshBoardEntitlement()"
require_text "$photo_library_saver" "PHAssetCreationRequest.forAsset()"

require_text "$board_store" "func purchase() async -> BoardPurchaseOutcome"
require_text "$board_store" "com.clovery.app.board.lifetime"
require_text "$board_store_client" "case .userCancelled:"
require_text "$board_store_client" "case .pending:"
require_text "$board_store_client" "StoreKit.Transaction.updates"
reject_text "$board_store" "isTestFlight"

require_text "$html" "window.__clovery_imageSaveResult = (outcome) =>"
require_text "$html" "saveError==='permissionDenied'"
require_text "$html" "messageHandlers?.openAppSettings?.postMessage"
require_text "$html" "minHeight:44"
require_text "$html" "const [purchaseNotice, setPurchaseNotice]"
require_text "$html" "window._boardRestoreResult = (outcome) =>"
require_text "$html" "购买请求正在等待批准，批准后会自动解锁"
require_text "$html" "没有找到可恢复的购买记录"
require_text "$html" "window._boardRestoreResult = null"
reject_text "$html" "window.__clovery_imageSaved"

node - "$web_view" "$html" "$app_source" <<'NODE'
const fs = require('node:fs');

const webViewSource = fs.readFileSync(process.argv[2], 'utf8');
const html = fs.readFileSync(process.argv[3], 'utf8');

function assert(condition, message) {
  if (!condition) throw new Error(`missing P0 behavior: ${message}`);
}

const restoreHandlerStart = webViewSource.indexOf('message.name == "restorePurchases"');
const restoreHandlerEnd = webViewSource.indexOf('message.name == "photoSave"', restoreHandlerStart);
const restoreHandler = webViewSource.slice(restoreHandlerStart, restoreHandlerEnd);
const restoreCall = restoreHandler.indexOf('let outcome = await BoardStore.shared.restore()');
const restoreCallback = restoreHandler.indexOf('BridgeJavaScript.boardRestoreResult(outcome)');
const unlockCallback = restoreHandler.indexOf('BridgeJavaScript.boardUnlockStatus(unlocked)');
const restoreReportingStart = restoreHandler.indexOf('isReportingBoardRestore = true');
const restoreReportingEnd = restoreHandler.indexOf('isReportingBoardRestore = false');
assert(restoreCall >= 0, 'restore outcome is awaited');
assert(restoreCall < restoreCallback && restoreCallback < unlockCallback, 'restore result precedes final unlock status');
assert(restoreReportingStart >= 0 && restoreReportingStart < restoreCall, 'restore reporting suppresses early entitlement publications');
assert(unlockCallback < restoreReportingEnd, 'restore reporting resumes after the final unlock status');

const observerOccurrences = webViewSource.match(/startObservingBoardStore\(\)/g) || [];
assert(observerOccurrences.length === 2, 'board store observer is defined and started exactly once');
const webViewBinding = webViewSource.indexOf('context.coordinator.webView = webView');
const observerStart = webViewSource.indexOf(
  'context.coordinator.startObservingBoardStore()',
  webViewBinding
);
assert(webViewBinding >= 0 && webViewBinding < observerStart, 'board store observation starts after WebView binding');
assert(webViewSource.includes('guard boardEntitlementCancellable == nil else { return }'), 'board store observation rejects duplicate subscriptions');
assert(webViewSource.includes('@MainActor\n        func startObservingBoardStore()'), 'board store observation starts on the main actor');
assert(webViewSource.includes('[weak self] unlocked in'), 'board entitlement subscription weakly captures the coordinator');
assert(webViewSource.includes('!self.isReportingBoardRestore else { return }'), 'board entitlement publications cannot overtake restore outcomes');
assert(webViewSource.includes('Task { @MainActor in\n            await BoardStore.shared.refresh()'), 'entitlement refresh awaits BoardStore on the main actor');

const sceneActive = appSource => appSource.includes('if phase == .active {')
  && appSource.includes('WebViewCoordinatorBridge.shared.refreshBoardEntitlement()');
assert(sceneActive(fs.readFileSync(process.argv[4], 'utf8')), 'active scenes refresh board entitlements');

function extractArrowBody(source, marker) {
  const markerIndex = source.indexOf(marker);
  assert(markerIndex >= 0, marker);
  const openingBrace = source.indexOf('{', markerIndex + marker.length);
  assert(openingBrace >= 0, `${marker} body`);

  let depth = 0;
  let quote = null;
  let escaped = false;
  for (let index = openingBrace; index < source.length; index += 1) {
    const character = source[index];
    if (quote) {
      if (escaped) escaped = false;
      else if (character === '\\') escaped = true;
      else if (character === quote) quote = null;
      continue;
    }
    if (character === '"' || character === "'" || character === '`') {
      quote = character;
      continue;
    }
    if (character === '{') depth += 1;
    if (character === '}') {
      depth -= 1;
      if (depth === 0) return source.slice(openingBrace + 1, index);
    }
  }
  throw new Error(`missing P0 behavior: unterminated ${marker}`);
}

function runCallback(body, outcome, lang = 'zh') {
  const state = {
    boardUnlocked: false,
    paywallOpen: true,
    purchaseError: false,
    purchasing: true,
    restoring: true,
    purchaseNotice: '',
  };
  const setter = key => value => { state[key] = value; };
  const pendingNotice = lang === 'zh'
    ? '购买请求正在等待批准，批准后会自动解锁'
    : 'Your purchase is awaiting approval and will unlock automatically once approved';
  const callback = new Function(
    'setBoardUnlocked', 'setPaywallOpen', 'setPurchaseError', 'setPurchasing',
    'setRestoring', 'setPurchaseNotice', 'lang', 'pendingNotice',
    `return (outcome) => {${body}};`
  )(
    setter('boardUnlocked'), setter('paywallOpen'), setter('purchaseError'),
    setter('purchasing'), setter('restoring'), setter('purchaseNotice'), lang, pendingNotice
  );
  callback(outcome);
  return state;
}

const purchaseBody = extractArrowBody(html, 'window._boardPurchaseResult = (outcome) =>');
const pending = runCallback(purchaseBody, 'pending');
assert(!pending.boardUnlocked, 'pending purchases stay locked');
assert(!pending.purchaseError, 'pending purchases are not errors');
assert(pending.purchaseNotice === '购买请求正在等待批准，批准后会自动解锁', 'pending purchases explain approval');
const pendingEnglish = runCallback(purchaseBody, 'pending', 'en');
assert(pendingEnglish.purchaseNotice === 'Your purchase is awaiting approval and will unlock automatically once approved', 'pending purchases explain approval in English');

const cancelled = runCallback(purchaseBody, 'cancelled');
assert(!cancelled.purchaseError && cancelled.purchaseNotice === '', 'cancelled purchases do not show errors or notices');

const restoreBody = extractArrowBody(html, 'window._boardRestoreResult = (outcome) =>');
const restored = runCallback(restoreBody, 'restored');
assert(!restored.purchaseError && restored.purchaseNotice === '购买已恢复', 'restored purchases show success');
const restoredEnglish = runCallback(restoreBody, 'restored', 'en');
assert(!restoredEnglish.purchaseError && restoredEnglish.purchaseNotice === 'Purchase restored', 'restored purchases show success in English');

const notFound = runCallback(restoreBody, 'notFound');
assert(!notFound.purchaseError && notFound.purchaseNotice === '没有找到可恢复的购买记录', 'missing restores show a non-error notice');
const notFoundEnglish = runCallback(restoreBody, 'notFound', 'en');
assert(!notFoundEnglish.purchaseError && notFoundEnglish.purchaseNotice === 'No restorable purchases were found', 'missing restores show a non-error notice in English');

const failed = runCallback(restoreBody, 'failed');
assert(failed.purchaseError && failed.purchaseNotice === '', 'failed restores clear notices and show retryable errors');
assert(!failed.restoring && failed.paywallOpen, 'failed restores leave the retry control available');
NODE

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
