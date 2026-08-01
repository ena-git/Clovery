#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
project="$repository_root/Clovery.xcodeproj/project.pbxproj"
scheme="$repository_root/Clovery.xcodeproj/xcshareddata/xcschemes/Clovery.xcscheme"
ui_tests="$repository_root/CloveryUITests"

require_text() {
  file=$1
  expected=$2
  label=$3
  if ! grep -Fq -- "$expected" "$file"; then
    echo "$label missing from $file" >&2
    exit 1
  fi
}

require_text "$project" 'CloveryUITests.xctest' "UI test product"
require_text "$project" 'path = CloveryUITests;' "UI test source group"
require_text "$project" 'productType = "com.apple.product-type.bundle.ui-testing";' "UI test target type"
require_text "$project" 'PRODUCT_BUNDLE_IDENTIFIER = com.clovery.app.UITests;' "UI test bundle ID"
require_text "$project" 'TEST_TARGET_NAME = Clovery;' "UI test host target"
require_text "$scheme" 'BuildableName = "CloveryUITests.xctest"' "shared scheme UI build"
require_text "$scheme" 'BlueprintName = "CloveryUITests"' "shared scheme UI test"
require_text "$ui_tests/AccountUpgradeUITests.swift" 'testAllReleaseRoutesRenderWithoutCrash' "route crash matrix"
require_text "$ui_tests/AccountUpgradeUITests.swift" 'testAccountDeletionRequiresExactCloveryID' "account deletion UI gate"
require_text "$ui_tests/AccountUpgradeUITests.swift" 'testReconciliationRoutesSurviveRelaunch' "interruption UI gate"
require_text "$ui_tests/AccountUpgradeUITests.swift" 'testIdentityClaimAndDiarySurviveRelaunch' "claim and diary relaunch gate"
require_text "$ui_tests/AccountUpgradeUITests.swift" 'testReconciliationSurvivesBackgroundAndForeground' "background recovery gate"
require_text "$ui_tests/AccountUpgradeUITests.swift" 'testRetryTransitionsOfflineStateBackToWorking' "offline retry gate"
require_text "$ui_tests/AccountUpgradeUITests.swift" 'testReconciliationSupportsReduceMotionAndDarkAppearance' "reduce motion gate"
require_text "$ui_tests/CloveryUITestCase.swift" '-CloveryVerificationFixture' "debug fixture launch"

ui_build_settings=$(awk '
  /AADD00000000000000000008 \/\* Debug \*\// { capture = 1 }
  /AADD00000000000000000009 \/\* Release \*\// { capture = 1 }
  capture { print }
  capture && /^\t\t};$/ { capture = 0 }
' "$project")
if printf '%s\n' "$ui_build_settings" | grep -Fq CODE_SIGN_ENTITLEMENTS; then
  echo "UI test target must not declare production signing entitlements" >&2
  exit 1
fi

echo "iOS UI test target contract verified"
