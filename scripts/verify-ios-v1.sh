#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repository_root"

destination=$(scripts/select-ios-simulator.sh)

node scripts/validate-v1-html.cjs
scripts/test-v1-p0-contract.sh
scripts/test-v1-bridge.sh
scripts/test-migration-zip.sh
Tests/IOSReleaseIdentityTests.sh
Tests/IOSReleaseEvidenceGateTests.sh
scripts/verify-ios-release-config.sh

xcodebuild \
  -project Clovery.xcodeproj \
  -scheme Clovery \
  -destination "$destination" \
  -derivedDataPath build/DerivedData-v1 \
  test \
  CODE_SIGNING_ALLOWED=NO

xcodebuild \
  -project Clovery.xcodeproj \
  -scheme Clovery \
  -configuration Release \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath build/DerivedData-v1-release \
  build \
  CODE_SIGNING_ALLOWED=NO
