#!/bin/sh

set -eu
umask 077

smoke_v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$smoke_v2_root/scripts/lib/staging-path.sh"
. "$smoke_v2_root/scripts/lib/ios-staging-smoke.sh"

smoke_initialize
trap smoke_cleanup EXIT HUP INT TERM

primary_token=$(smoke_secure_file "${LEGACY_ENTITLEMENT_PRIMARY_ACCESS_TOKEN_FILE:-}") || smoke_configuration_fail
other_account_token=$(smoke_secure_file "${LEGACY_ENTITLEMENT_OTHER_ACCESS_TOKEN_FILE:-}") || smoke_configuration_fail
second_device_token=$(smoke_secure_file "${LEGACY_ENTITLEMENT_SECOND_DEVICE_ACCESS_TOKEN_FILE:-}") || smoke_configuration_fail
legacy_claim_request=$(smoke_secure_file "${LEGACY_APPLE_CLAIM_REQUEST_FILE:-}") || smoke_configuration_fail
product_id=${APPLE_BILLING_PRODUCT_ID:-}
[ "$product_id" = "com.clovery.app.board.lifetime" ] || smoke_configuration_fail

first_response="$smoke_work_directory/first-claim.json"

scenario_first_claim() {
  smoke_request POST /v1/billing/apple/legacy-claims "$legacy_claim_request" \
    "$primary_token" "$first_response" 200 || return 1
  "$smoke_jq_bin" -e --arg product "$product_id" \
    '.product_id == $product and .state == "active"' "$first_response" >/dev/null 2>&1
}

scenario_same_account_replay() {
  replay_response="$smoke_work_directory/same-account-replay.json"
  first_summary="$smoke_work_directory/first-entitlement-summary.json"
  replay_summary="$smoke_work_directory/replay-entitlement-summary.json"
  smoke_request POST /v1/billing/apple/legacy-claims "$legacy_claim_request" \
    "$primary_token" "$replay_response" 200 || return 1
  "$smoke_jq_bin" -S '{product_id, state, source_storefront, source_transaction_id}' \
    "$first_response" >"$first_summary" 2>/dev/null || return 1
  "$smoke_jq_bin" -S '{product_id, state, source_storefront, source_transaction_id}' \
    "$replay_response" >"$replay_summary" 2>/dev/null || return 1
  cmp -s "$first_summary" "$replay_summary"
}

scenario_other_account_blocked() {
  blocked_response="$smoke_work_directory/other-account.json"
  smoke_request POST /v1/billing/apple/legacy-claims "$legacy_claim_request" \
    "$other_account_token" "$blocked_response" 409 || return 1
  smoke_assert_json "$blocked_response" '.code == "apple_transaction_claimed"'
}

scenario_second_device() {
  entitlement_response="$smoke_work_directory/second-device.json"
  smoke_request GET /v1/account/entitlements - "$second_device_token" "$entitlement_response" 200 || return 1
  "$smoke_jq_bin" -e --arg product "$product_id" \
    '[.entitlements[] | select(.product_id == $product and .state == "active")] | length == 1' \
    "$entitlement_response" >/dev/null 2>&1
}

smoke_run_scenario "legacy transaction first claim -> active entitlement" scenario_first_claim
smoke_run_scenario "same-account replay -> same entitlement" scenario_same_account_replay
smoke_run_scenario "other-account claim -> blocked" scenario_other_account_blocked
smoke_run_scenario "second device -> same entitlement list" scenario_second_device
