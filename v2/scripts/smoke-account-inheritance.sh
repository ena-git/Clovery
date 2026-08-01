#!/bin/sh

set -eu
umask 077

smoke_v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$smoke_v2_root/scripts/lib/staging-path.sh"
. "$smoke_v2_root/scripts/lib/ios-staging-smoke.sh"

smoke_initialize
trap smoke_cleanup EXIT HUP INT TERM

bound_request=$(smoke_secure_file "${BOUND_APPLE_COMPLETE_REQUEST_FILE:-}") || smoke_configuration_fail
bound_expected_root=$(smoke_secure_file "${BOUND_APPLE_EXPECTED_ROOT_FILE:-}") || smoke_configuration_fail
unbound_request=$(smoke_secure_file "${UNBOUND_APPLE_COMPLETE_REQUEST_FILE:-}") || smoke_configuration_fail
claim_registration_template=$(smoke_secure_file "${CLAIM_REGISTRATION_TEMPLATE_FILE:-}") || smoke_configuration_fail
claim_replay_template=$(smoke_secure_file "${CLAIM_REPLAY_REGISTRATION_TEMPLATE_FILE:-}") || smoke_configuration_fail
plain_registration_request=$(smoke_secure_file "${PLAIN_REGISTRATION_REQUEST_FILE:-}") || smoke_configuration_fail
migration_retry_fixture=$(smoke_secure_directory "${MIGRATION_RETRY_FIXTURE_DIR:-}") || smoke_configuration_fail
migration_duplicate_fixture=$(smoke_secure_directory "${MIGRATION_CONTENT_DUPLICATE_FIXTURE_DIR:-}") || smoke_configuration_fail
migration_conflict_fixture=$(smoke_secure_directory "${MIGRATION_ID_CONFLICT_FIXTURE_DIR:-}") || smoke_configuration_fail

bound_response="$smoke_work_directory/bound.json"
bound_token="$smoke_work_directory/bound.token"
claim_response="$smoke_work_directory/claim.json"
claim_token="$smoke_work_directory/claim.token"
claimed_request="$smoke_work_directory/claimed-request.json"
claimed_response="$smoke_work_directory/claimed.json"
claimed_token="$smoke_work_directory/claimed.token"
plain_response="$smoke_work_directory/plain.json"
plain_token="$smoke_work_directory/plain.token"

scenario_bound_apple() {
  smoke_request POST /v1/auth/federated/apple/complete "$bound_request" - "$bound_response" 200 || return 1
  smoke_assert_json "$bound_response" \
    '(.account_id | type == "string") and (.vault_id | type == "string") and (.access_token | type == "string")' || return 1
  smoke_compare_roots "$bound_response" "$bound_expected_root" || return 1
  smoke_extract_json "$bound_response" '.access_token' "$bound_token" || return 1
  profile="$smoke_work_directory/bound-profile.json"
  smoke_request GET /v1/account - "$bound_token" "$profile" 200 || return 1
  smoke_assert_json "$profile" '[.bindings[] | select(.provider == "apple")] | length == 1'
}

scenario_unbound_apple() {
  smoke_request POST /v1/auth/federated/apple/complete "$unbound_request" - "$claim_response" 202 || return 1
  smoke_assert_json "$claim_response" \
    '.status == "identity_claim_required" and .provider == "apple" and (.account_id? == null) and (.vault_id? == null)' || return 1
  smoke_extract_json "$claim_response" '.identity_claim_token' "$claim_token"
}

scenario_claim_registration() {
  smoke_assert_json "$claim_registration_template" \
    '.recovery_method == "bound_identity" and (.source_kind == "legacy_local" or .source_kind == "legacy_cloudkit")' || return 1
  "$smoke_jq_bin" --rawfile claim "$claim_token" \
    '. + {identity_claim_token: ($claim | gsub("[\\r\\n]+$"; ""))}' \
    "$claim_registration_template" >"$claimed_request" 2>/dev/null || return 1
  smoke_request POST /v1/auth/accounts "$claimed_request" - "$claimed_response" 201 || return 1
  smoke_assert_json "$claimed_response" \
    '(.account_id | type == "string") and (.vault_id | type == "string") and (.access_token | type == "string")' || return 1
  smoke_extract_json "$claimed_response" '.access_token' "$claimed_token" || return 1

  profile="$smoke_work_directory/claimed-profile.json"
  bootstrap="$smoke_work_directory/claimed-bootstrap.json"
  smoke_request GET /v1/account - "$claimed_token" "$profile" 200 || return 1
  smoke_assert_json "$profile" '[.bindings[] | select(.provider == "apple")] | length == 1' || return 1
  smoke_request GET /v1/account/bootstrap - "$claimed_token" "$bootstrap" 200 || return 1
  source_kind=$("$smoke_jq_bin" -r '.source_kind' "$claim_registration_template") || return 1
  "$smoke_jq_bin" -e --arg source "$source_kind" \
    '.source_kind == $source and .stages.identity == "complete" and (.status | type == "string")' \
    "$bootstrap" >/dev/null 2>&1
}

scenario_claim_retry() {
  retry_response="$smoke_work_directory/claimed-retry.json"
  smoke_request POST /v1/auth/accounts "$claimed_request" - "$retry_response" 201 || return 1
  smoke_compare_roots "$claimed_response" "$retry_response"
}

scenario_claim_replay() {
  replay_request="$smoke_work_directory/claim-replay.json"
  replay_response="$smoke_work_directory/claim-replay-response.json"
  "$smoke_jq_bin" --rawfile claim "$claim_token" \
    '. + {identity_claim_token: ($claim | gsub("[\\r\\n]+$"; ""))}' \
    "$claim_replay_template" >"$replay_request" 2>/dev/null || return 1
  smoke_request POST /v1/auth/accounts "$replay_request" - "$replay_response" 409 || return 1
  smoke_assert_json "$replay_response" '.code == "identity_claim_consumed"'
}

scenario_plain_registration() {
  smoke_request POST /v1/auth/accounts "$plain_registration_request" - "$plain_response" 201 || return 1
  smoke_assert_json "$plain_response" \
    '(.account_id | type == "string") and (.vault_id | type == "string") and (.access_token | type == "string")' || return 1
  smoke_extract_json "$plain_response" '.access_token' "$plain_token" || return 1
  bootstrap="$smoke_work_directory/plain-bootstrap.json"
  smoke_request GET /v1/account/bootstrap - "$plain_token" "$bootstrap" 200 || return 1
  smoke_assert_json "$bootstrap" \
    '.source_kind == "new_install" and .stages.identity == "complete" and .stages.migration == "complete"'
}

migration_fixture_file() {
  fixture_directory=$1
  filename=$2
  smoke_secure_file "$fixture_directory/$filename"
}

run_migration_fixture() {
  fixture_directory=$1
  expectation=$2
  create_request=$(migration_fixture_file "$fixture_directory" create.json) || return 1
  entries_file=$(migration_fixture_file "$fixture_directory" entries.ndjson) || return 1
  migration_id=$("$smoke_jq_bin" -er '.migration_id' "$create_request" 2>/dev/null) || return 1
  printf '%s\n' "$migration_id" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' || return 1

  if [ -f "$fixture_directory/precondition.json" ]; then
    precondition=$(migration_fixture_file "$fixture_directory" precondition.json) || return 1
    precondition_response="$smoke_work_directory/precondition-$expectation.json"
    smoke_request POST /v1/vault/sync/push "$precondition" "$claimed_token" "$precondition_response" 200 || return 1
  fi

  create_response="$smoke_work_directory/create-$expectation.json"
  smoke_request POST /v1/vault/migrations "$create_request" "$claimed_token" "$create_response" 201 || return 1
  entry_request="$smoke_work_directory/entry-$expectation.json"
  entry_response="$smoke_work_directory/entry-$expectation-response.json"
  entry_number=0
  while IFS= read -r entry || [ -n "$entry" ]; do
    [ -n "$entry" ] || continue
    entry_number=$((entry_number + 1))
    printf '%s\n' "$entry" >"$entry_request"
    smoke_request POST "/v1/vault/migrations/$migration_id/entries" \
      "$entry_request" "$claimed_token" "$entry_response" 204 || return 1
    if [ "$expectation" = "retry" ] && [ "$entry_number" -eq 1 ]; then
      smoke_request POST "/v1/vault/migrations/$migration_id/entries" \
        "$entry_request" "$claimed_token" "$entry_response" 204 || return 1
    fi
  done <"$entries_file"

  verify_response="$smoke_work_directory/verify-$expectation.json"
  report_response="$smoke_work_directory/report-$expectation.json"
  smoke_request POST "/v1/vault/migrations/$migration_id/verify" - \
    "$claimed_token" "$verify_response" 200 || return 1
  smoke_request GET "/v1/vault/migrations/$migration_id/report" - \
    "$claimed_token" "$report_response" 200 || return 1

  case "$expectation" in
    retry)
      report_check='.status == "verified" and .inserted_entries == 1 and .duplicate_entries == 0 and .conflict_copies == 0'
      ;;
    content_duplicate)
      report_check='.status == "verified" and .inserted_entries == 1 and .duplicate_entries == 1 and .conflict_copies == 0'
      ;;
    id_conflict)
      report_check='.status == "verified" and .inserted_entries == 1 and .duplicate_entries == 0 and .conflict_copies == 1'
      ;;
    *) return 1 ;;
  esac
  smoke_assert_json "$verify_response" "$report_check" || return 1
  smoke_assert_json "$report_response" "$report_check"
}

smoke_run_scenario "bound Apple -> original account/vault" scenario_bound_apple
smoke_run_scenario "unbound Apple -> 202 claim, no account" scenario_unbound_apple
smoke_run_scenario "claim registration -> one account/vault/binding/job" scenario_claim_registration
smoke_run_scenario "same request retry -> same account/vault" scenario_claim_retry
smoke_run_scenario "claim replay with another request -> conflict" scenario_claim_replay
smoke_run_scenario "plain Clovery registration/login -> bootstrap job" scenario_plain_registration
smoke_run_scenario "same diary migration twice -> one result" run_migration_fixture "$migration_retry_fixture" retry
smoke_run_scenario "different-ID duplicate -> one result" run_migration_fixture "$migration_duplicate_fixture" content_duplicate
smoke_run_scenario "same-ID conflict -> two preserved entries" run_migration_fixture "$migration_conflict_fixture" id_conflict
