#!/usr/bin/env bash

created_device_ids=()

cleanup_simulator_matrix() {
  for device_id in "${created_device_ids[@]:-}"; do
    [[ -n "$device_id" ]] || continue
    xcrun simctl shutdown "$device_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$device_id" >/dev/null 2>&1 || true
  done
  if [[ -n "${matrix_root:-}" && -d "$matrix_root" ]]; then
    rm -rf "$matrix_root"
  fi
}

matrix_failure() {
  local label=$1
  local exit_code=$2
  printf -- '- %s: FAIL (exit %s)\n' "$label" "$exit_code" >>"$matrix_summary"
  printf '%s\n' "Clovery iOS 1.1.0 simulator matrix"
  cat "$matrix_summary"
  printf '%s\n' "Raw logs, result bundles, build products, and temporary simulators will be removed."
  exit "$exit_code"
}

latest_ios_runtime() {
  xcrun simctl list runtimes available | awk -F ' - ' '
    /^iOS / { print $NF; exit }
  '
}

run_device_matrix() {
  local label=$1
  local slug=$2
  local device_type=$3
  local device_id
  local result_bundle="$matrix_root/$slug.xcresult"
  local log="$matrix_root/$slug.log"
  local result_json="$matrix_root/$slug-summary.json"

  if ! device_id=$(xcrun simctl create "Clovery-W10-$slug-$$" "$device_type" "$runtime_id"); then
    matrix_failure "$label simulator creation" 1
  fi
  created_device_ids+=("$device_id")

  if ! CLOVERY_RELEASE_API_BASE_URL="$CLOVERY_RELEASE_API_BASE_URL" xcodebuild -quiet \
    -project "$repository_root/Clovery.xcodeproj" \
    -scheme Clovery \
    -destination "id=$device_id" \
    -derivedDataPath "$matrix_root/DerivedData" \
    -resultBundlePath "$result_bundle" \
    test \
    -only-testing:CloveryUITests/AccountUpgradeUITests/testAllReleaseRoutesRenderWithoutCrash \
    -only-testing:CloveryUITests/AccountUpgradeUITests/testAccessibilityRoutesKeepRequiredActionsReachable \
    -only-testing:CloveryUITests/AccountUpgradeUITests/testAccountDeletionRequiresExactCloveryID \
    >"$log" 2>&1
  then
    matrix_failure "$label UI matrix" 1
  fi

  if ! xcrun xcresulttool get test-results summary \
    --path "$result_bundle" >"$result_json" 2>>"$log"
  then
    matrix_failure "$label result audit" 1
  fi

  local failed_tests
  local skipped_tests
  local passed_tests
  failed_tests=$(/usr/bin/plutil -extract failedTests raw -o - "$result_json")
  skipped_tests=$(/usr/bin/plutil -extract skippedTests raw -o - "$result_json")
  passed_tests=$(/usr/bin/plutil -extract passedTests raw -o - "$result_json")
  if [[ "$failed_tests" != 0 || "$skipped_tests" != 0 ]]; then
    matrix_failure "$label result audit" 1
  fi

  printf -- '- %s: PASS (%s tests, %s)\n' \
    "$label" "$passed_tests" "$runtime_label" >>"$matrix_summary"
  xcrun simctl shutdown "$device_id" >/dev/null 2>&1 || true
  xcrun simctl delete "$device_id" >/dev/null 2>&1 || true
}

run_ios_simulator_matrix() {
  repository_root=$1
  CLOVERY_RELEASE_API_BASE_URL=${CLOVERY_RELEASE_API_BASE_URL:-https://api.clovery.cn}
  if [[ "$CLOVERY_RELEASE_API_BASE_URL" != https://api.clovery.cn ]]; then
    echo "CLOVERY_RELEASE_API_BASE_URL must be https://api.clovery.cn" >&2
    exit 1
  fi
  export CLOVERY_RELEASE_API_BASE_URL

  matrix_root=$(mktemp -d /private/tmp/clovery-ios-simulator-matrix.XXXXXX)
  matrix_summary="$matrix_root/summary.txt"
  : >"$matrix_summary"
  trap cleanup_simulator_matrix EXIT HUP INT TERM

  runtime_id=${CLOVERY_SIMULATOR_RUNTIME:-$(latest_ios_runtime)}
  if [[ -z "$runtime_id" ]]; then
    echo "no available iOS Simulator runtime" >&2
    exit 1
  fi
  runtime_label=$(xcrun simctl list runtimes available | awk -v runtime="$runtime_id" '
    index($0, runtime) { sub(/[[:space:]]+-[[:space:]]+com\.apple\..*$/, ""); print; exit }
  ')

  run_device_matrix \
    "iPhone SE (3rd generation)" \
    iphone-se-3 \
    com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation
  run_device_matrix \
    "iPhone 13 mini" \
    iphone-13-mini \
    com.apple.CoreSimulator.SimDeviceType.iPhone-13-mini
  run_device_matrix \
    "iPhone 16 Pro" \
    iphone-16-pro \
    com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro
  run_device_matrix \
    "iPhone 16 Pro Max" \
    iphone-16-pro-max \
    com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max

  printf '%s\n' "Clovery iOS 1.1.0 simulator matrix"
  cat "$matrix_summary"
  printf '%s\n' "All temporary simulators and build products will be removed."
}
