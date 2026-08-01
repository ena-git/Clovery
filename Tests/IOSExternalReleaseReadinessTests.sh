#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
release_dir="$repository_root/docs/release"
device="$release_dir/ios-1.1.0-device-acceptance.md"
storekit="$release_dir/ios-1.1.0-storekit-acceptance.md"
production="$release_dir/ios-1.1.0-production-checklist.md"
monitoring="$release_dir/ios-1.1.0-monitoring.md"
acceptance="$release_dir/ios-1.1.0-acceptance.md"
incident="$repository_root/docs/incidents/2026-07-11-v1-photo-iap-p0.md"

require_text() {
  file=$1
  expected=$2
  label=$3
  if ! grep -Fq -- "$expected" "$file"; then
    echo "$label missing from $file" >&2
    exit 1
  fi
}

for file in "$device" "$storekit" "$production" "$monitoring"; do
  if [ ! -f "$file" ]; then
    echo "missing external release runbook: $file" >&2
    exit 1
  fi
  require_text "$file" '**执行状态：** `NOT_RUN`' "truthful external status"
done

require_text "$device" 'Device A' "legacy upgrade device"
require_text "$device" 'Device B' "cross-device inheritance device"
require_text "$device" 'Photos P0' "physical Photos gate"
require_text "$device" '旧 Apple 已绑定用户' "legacy Apple gate"
require_text "$storekit" 'com.clovery.app.board.lifetime' "StoreKit product"
require_text "$storekit" 'Non-Consumable' "StoreKit product type"
require_text "$storekit" 'appAccountToken' "account-bound purchase"
require_text "$storekit" 'scripts/verify-ios-1.1.0-archive.sh' "signed archive audit"
require_text "$storekit" 'TestFlight' "TestFlight gate"
require_text "$production" '分阶段发布' "phased release"
require_text "$production" 'ios-v1.1.0' "GitHub release tag"
require_text "$monitoring" 'P0' "P0 stop threshold"
require_text "$monitoring" 'bootstrap' "bootstrap monitoring"
require_text "$acceptance" 'ios-1.1.0-device-acceptance.md' "device runbook link"
require_text "$acceptance" 'ios-1.1.0-storekit-acceptance.md' "StoreKit runbook link"
require_text "$acceptance" 'ios-1.1.0-production-checklist.md' "production runbook link"
require_text "$incident" '受影响用户修复验收' "affected-user closure gate"

if grep -Eq '设备 UDID|Apple ID：|transaction_id|signedTransactionInfo' \
  "$device" "$storekit" "$production" "$monitoring"; then
  echo "external release docs must not request or store restricted identifiers" >&2
  exit 1
fi

echo "iOS external release readiness contracts verified"
