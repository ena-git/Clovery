#!/bin/sh

cleanup() {
  if [ -n "${verification_root:-}" ] && [ -d "$verification_root" ]; then
    rm -rf "$verification_root"
  fi
}

run_gate() {
  gate_label=$1
  gate_slug=$2
  shift 2
  gate_log="$verification_root/$gate_slug.log"

  if "$@" >"$gate_log" 2>&1; then
    printf -- '- %s: PASS\n' "$gate_label" >>"$verification_summary"
    return
  else
    gate_status=$?
  fi

  printf -- '- %s: FAIL (exit %s)\n' "$gate_label" "$gate_status" >>"$verification_summary"
  printf '%s\n' "Clovery iOS 1.1.0 automated verification"
  cat "$verification_summary"
  printf '%s\n' "Raw command output was removed with the temporary verification directory."
  exit "$gate_status"
}

verify_toolchain() {
  xcode_version=$(xcodebuild -version)
  developer_directory=$(xcode-select -p)
  if printf '%s\n%s\n' "$xcode_version" "$developer_directory" | grep -qi beta; then
    echo "beta Xcode is not allowed" >&2
    return 1
  fi
  command -v node >/dev/null
  command -v go >/dev/null
  command -v xcrun >/dev/null
}

verify_backend() {
  (
    cd "$repository_root/v2/services/api"
    GOCACHE="$verification_root/go-build" go test -race ./...
    GOCACHE="$verification_root/go-build" go build -o "$verification_root/clovery-api" ./cmd/api
  )
}

verify_staging_contracts() {
  "$repository_root/v2/scripts/test-account-upgrade-operations.sh"
  "$repository_root/v2/scripts/test-ios-1.1.0-staging-smoke.sh"
  "$repository_root/v2/scripts/test-staging-configuration.sh"
  "$repository_root/v2/scripts/test-staging-data-safety.sh"
  "$repository_root/v2/scripts/test-staging-smoke-evidence.sh"
}

verify_static_ios_contracts() {
  node "$repository_root/scripts/validate-v1-html.cjs"
  "$repository_root/scripts/test-v1-p0-contract.sh"
  "$repository_root/scripts/test-v1-bridge.sh"
  "$repository_root/scripts/test-migration-zip.sh"
}

verify_release_contracts() {
  "$repository_root/Tests/IOS110VerificationScriptTests.sh"
  "$repository_root/Tests/IOS110ArchiveVerificationScriptTests.sh"
  "$repository_root/Tests/IOSExternalReleaseReadinessTests.sh"
  "$repository_root/Tests/IOSUITestTargetContractTests.sh"
  "$repository_root/Tests/IOSSimulatorMatrixScriptTests.sh"
  "$repository_root/Tests/IOSReleaseIdentityTests.sh"
  "$repository_root/Tests/IOSReleaseEvidenceGateTests.sh"
  "$repository_root/Tests/RepositoryHygieneTests.sh"
  "$repository_root/scripts/verify-ios-release-config.sh"
  "$repository_root/scripts/verify-repository-hygiene.sh"
  git -C "$repository_root" diff --check
}

select_simulator() {
  "$repository_root/scripts/select-ios-simulator.sh" >"$verification_root/destination.txt"
}

verify_xctest() {
  destination=$(cat "$verification_root/destination.txt")
  CLOVERY_RELEASE_API_BASE_URL="$CLOVERY_RELEASE_API_BASE_URL" xcodebuild -quiet \
    -project "$repository_root/Clovery.xcodeproj" \
    -scheme Clovery \
    -destination "$destination" \
    -derivedDataPath "$verification_root/DerivedData-test" \
    -resultBundlePath "$verification_root/Clovery-1.1.0.xcresult" \
    test
}

verify_xctest_summary() {
  xcrun xcresulttool get test-results summary \
    --path "$verification_root/Clovery-1.1.0.xcresult" \
    >"$verification_root/xctest-summary.json"

  xctest_result=$(/usr/bin/plutil -extract result raw -o - "$verification_root/xctest-summary.json")
  xctest_failed=$(/usr/bin/plutil -extract failedTests raw -o - "$verification_root/xctest-summary.json")
  xctest_skipped=$(/usr/bin/plutil -extract skippedTests raw -o - "$verification_root/xctest-summary.json")
  xctest_passed=$(/usr/bin/plutil -extract passedTests raw -o - "$verification_root/xctest-summary.json")

  [ "$xctest_result" = "Passed" ]
  [ "$xctest_failed" = "0" ]
  [ "$xctest_skipped" = "0" ]
  printf '%s\n' "$xctest_passed" >"$verification_root/xctest-passed.txt"
  /usr/bin/plutil -extract devicesAndConfigurations.0.device.deviceName raw -o - \
    "$verification_root/xctest-summary.json" >"$verification_root/simulator-name.txt"
  /usr/bin/plutil -extract devicesAndConfigurations.0.device.osVersion raw -o - \
    "$verification_root/xctest-summary.json" >"$verification_root/simulator-os.txt"
}

verify_release_build() {
  CLOVERY_RELEASE_API_BASE_URL="$CLOVERY_RELEASE_API_BASE_URL" xcodebuild -quiet \
    -project "$repository_root/Clovery.xcodeproj" \
    -scheme Clovery \
    -configuration Release \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$verification_root/DerivedData-release" \
    build \
    CODE_SIGNING_ALLOWED=NO
}

print_verification_summary() {
  printf '%s\n' "Clovery iOS 1.1.0 automated verification"
  cat "$verification_summary"
  printf -- '- XCTest: %s passed, 0 failed, 0 skipped\n' \
    "$(cat "$verification_root/xctest-passed.txt")"
  printf -- '- Simulator: %s, iOS %s\n' \
    "$(cat "$verification_root/simulator-name.txt")" \
    "$(cat "$verification_root/simulator-os.txt")"
  printf '%s\n' "All transient logs and build products will be removed."
}

run_ios_release_verification() {
  repository_root=$1
  expected_api_url=https://api.clovery.cn
  CLOVERY_RELEASE_API_BASE_URL=${CLOVERY_RELEASE_API_BASE_URL:-$expected_api_url}
  if [ "$CLOVERY_RELEASE_API_BASE_URL" != "$expected_api_url" ]; then
    echo "CLOVERY_RELEASE_API_BASE_URL must be $expected_api_url" >&2
    exit 1
  fi
  export CLOVERY_RELEASE_API_BASE_URL

  verification_root=$(mktemp -d /private/tmp/clovery-ios-1.1.0.XXXXXX)
  verification_summary="$verification_root/summary.txt"
  : >"$verification_summary"
  trap cleanup EXIT HUP INT TERM

  run_gate "Stable toolchain" toolchain verify_toolchain
  run_gate "Go race tests and build" backend verify_backend
  run_gate "Staging operation contracts" staging-contracts verify_staging_contracts
  run_gate "HTML, bridge, photo and migration contracts" static-ios verify_static_ios_contracts
  run_gate "Release identity, privacy and hygiene" release-contracts verify_release_contracts
  run_gate "Simulator selection" simulator-selection select_simulator
  run_gate "Complete XCTest suite" xctest verify_xctest
  run_gate "XCTest result audit" xctest-summary verify_xctest_summary
  run_gate "Unsigned Release simulator build" release-build verify_release_build
  print_verification_summary
}
