#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
entrypoint="$repository_root/scripts/verify-ios-1.1.0-archive.sh"
implementation="$repository_root/scripts/lib/ios-archive-verification.sh"

require_text() {
  file=$1
  expected=$2
  label=$3
  if ! grep -Fq -- "$expected" "$file"; then
    echo "$label missing from $file" >&2
    exit 1
  fi
}

if [ ! -x "$entrypoint" ]; then
  echo "iOS archive verifier must exist and be executable" >&2
  exit 1
fi
if [ ! -f "$implementation" ]; then
  echo "iOS archive verification must be modular" >&2
  exit 1
fi

require_text "$implementation" 'com.clovery.app' "main bundle identity"
require_text "$implementation" 'com.clovery.app.CloveryWidget' "widget bundle identity"
require_text "$implementation" '1.1.0' "marketing version"
require_text "$implementation" '15' "build number"
require_text "$implementation" 'M92TBSSR2R' "team identity"
require_text "$implementation" 'group.com.clovery.app' "app group identity"
require_text "$implementation" 'iCloud.com.clovery.app' "iCloud identity"
require_text "$implementation" 'aps-environment' "push entitlement audit"
require_text "$implementation" 'PrivacyInfo.xcprivacy' "privacy manifest audit"
require_text "$implementation" 'Clovery.storekit' "local StoreKit exclusion"
require_text "$implementation" 'mktemp -d /private/tmp/clovery-ios-archive.' "private audit root"
require_text "$implementation" 'trap cleanup_ios_archive_verification EXIT HUP INT TERM' "audit cleanup trap"

if "$entrypoint" "$repository_root/does-not-exist.xcarchive" >/dev/null 2>&1; then
  echo "archive verifier must reject a missing archive" >&2
  exit 1
fi

echo "iOS 1.1.0 signed archive verifier contract verified"
