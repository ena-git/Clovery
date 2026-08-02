#!/bin/sh

set -eu

v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
account_smoke="$v2_root/scripts/smoke-account-inheritance.sh"
billing_smoke="$v2_root/scripts/smoke-legacy-entitlement.sh"

fail() {
  echo "iOS 1.1.0 staging smoke test failed: $1" >&2
  exit 1
}

[ -x "$account_smoke" ] || fail "missing executable smoke-account-inheritance.sh"
[ -x "$billing_smoke" ] || fail "missing executable smoke-legacy-entitlement.sh"

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/clovery-ios-staging-smoke.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
evidence_directory="$temporary_directory/evidence"
mkdir -p "$evidence_directory"
chmod 700 "$evidence_directory"

write_json() {
  destination=$1
  contents=$2
  printf '%s\n' "$contents" >"$destination"
  chmod 600 "$destination"
}

write_json "$evidence_directory/bound-complete.json" \
  '{"intent_id":"10000000-0000-4000-8000-000000000001","nonce":"bound-nonce","authorization_code":"bound-code","device":{"device_id":"10000000-0000-4000-8000-000000000002","platform":"ios","display_name":"Bound iPhone"}}'
write_json "$evidence_directory/bound-root.json" \
  '{"account_id":"11111111-1111-4111-8111-111111111111","vault_id":"22222222-2222-4222-8222-222222222222"}'
write_json "$evidence_directory/unbound-complete.json" \
  '{"intent_id":"10000000-0000-4000-8000-000000000003","nonce":"unbound-nonce","authorization_code":"unbound-code","device":{"device_id":"10000000-0000-4000-8000-000000000004","platform":"ios","display_name":"Unbound iPhone"}}'
write_json "$evidence_directory/claim-registration.json" \
  '{"login_id":"claimed_smoke","password":"eight-safe-words","recovery_method":"bound_identity","registration_request_id":"10000000-0000-4000-8000-000000000005","source_kind":"legacy_local","device":{"device_id":"10000000-0000-4000-8000-000000000006","platform":"ios","display_name":"Claimed iPhone"}}'
write_json "$evidence_directory/claim-replay.json" \
  '{"login_id":"replay_smoke","password":"eight-safe-words","recovery_method":"bound_identity","registration_request_id":"10000000-0000-4000-8000-000000000007","source_kind":"legacy_local","device":{"device_id":"10000000-0000-4000-8000-000000000008","platform":"ios","display_name":"Replay iPhone"}}'
write_json "$evidence_directory/plain-registration.json" \
  '{"login_id":"plain_smoke","password":"eight-safe-words","recovery_method":"recovery_codes","device":{"device_id":"10000000-0000-4000-8000-000000000009","platform":"ios","display_name":"Plain iPhone"}}'

for fixture in retry duplicate conflict; do
  mkdir -p "$evidence_directory/migration-$fixture"
  chmod 700 "$evidence_directory/migration-$fixture"
done
write_json "$evidence_directory/migration-retry/create.json" \
  '{"migration_id":"a1000000-0000-4000-8000-000000000001","format_version":1,"source":"v1_bundle","entry_count":1,"asset_count":0,"total_bytes":2,"manifest_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","manifest_base64":"e30="}'
write_json "$evidence_directory/migration-retry/entries.ndjson" \
  '{"entry_id":"a1000000-0000-4000-8000-000000000002","payload":{},"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'
write_json "$evidence_directory/migration-duplicate/create.json" \
  '{"migration_id":"a2000000-0000-4000-8000-000000000001","format_version":1,"source":"v1_bundle","entry_count":2,"asset_count":0,"total_bytes":4,"manifest_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","manifest_base64":"e30="}'
cat >"$evidence_directory/migration-duplicate/entries.ndjson" <<'EOF'
{"entry_id":"a2000000-0000-4000-8000-000000000002","payload":{},"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
{"entry_id":"a2000000-0000-4000-8000-000000000003","payload":{},"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
EOF
chmod 600 "$evidence_directory/migration-duplicate/entries.ndjson"
write_json "$evidence_directory/migration-conflict/create.json" \
  '{"migration_id":"a3000000-0000-4000-8000-000000000001","format_version":1,"source":"v1_bundle","entry_count":1,"asset_count":0,"total_bytes":2,"manifest_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","manifest_base64":"e30="}'
write_json "$evidence_directory/migration-conflict/entries.ndjson" \
  '{"entry_id":"a3000000-0000-4000-8000-000000000002","payload":{},"sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'
write_json "$evidence_directory/migration-conflict/precondition.json" \
  '{"operations":[{"operation_id":"a3000000-0000-4000-8000-000000000003","entry_id":"a3000000-0000-4000-8000-000000000002","base_revision":0,"payload":{}}]}'

printf '%s' 'primary-access-token' >"$evidence_directory/primary.token"
printf '%s' 'other-access-token' >"$evidence_directory/other.token"
printf '%s' 'second-device-token' >"$evidence_directory/second-device.token"
chmod 600 "$evidence_directory/primary.token" "$evidence_directory/other.token" "$evidence_directory/second-device.token"
write_json "$evidence_directory/legacy-claim.json" \
  '{"signed_transaction_info":"signed-transaction-secret-fixture","environment":"sandbox"}'

fake_curl="$temporary_directory/fake-curl"
cat >"$fake_curl" <<'EOF'
#!/bin/sh
set -eu

method=GET
output=
write_out=
data_file=
token=
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -X) method=$2; shift 2 ;;
    -o) output=$2; shift 2 ;;
    -w) write_out=$2; shift 2 ;;
    -H)
      header=${2#@}
      if [ -f "$header" ] && grep -q '^Authorization: Bearer ' "$header"; then
        token=$(sed 's/^Authorization: Bearer //' "$header")
      fi
      shift 2
      ;;
    --data-binary) data_file=${2#@}; shift 2 ;;
    --connect-timeout|--max-time) shift 2 ;;
    -sS) shift ;;
    *) url=$1; shift ;;
  esac
done

path=${url#https://api.staging.clovery.cn}
body='{}'
status=404
case "$method $path" in
  'POST /v1/auth/federated/apple/complete')
    if grep -q 'bound-code' "$data_file" && ! grep -q 'unbound-code' "$data_file"; then
      if [ "${FAKE_BOUND_FAILURE:-false}" = "true" ]; then
        status=500
        body='{"code":"internal_error","debug_token":"must-never-leak"}'
      else
        status=200
        body='{"account_id":"11111111-1111-4111-8111-111111111111","vault_id":"22222222-2222-4222-8222-222222222222","access_token":"bound-access-token","access_token_expires_in":900,"refresh_token":"bound-refresh-token"}'
      fi
    else
      status=202
      body='{"status":"identity_claim_required","provider":"apple","identity_claim_token":"opaque_claim_token","expires_in":600}'
    fi
    ;;
  'POST /v1/auth/accounts')
    if grep -q 'replay_smoke' "$data_file"; then
      status=409
      body='{"code":"identity_claim_consumed","message":"redacted"}'
    elif grep -q 'claimed_smoke' "$data_file"; then
      status=201
      body='{"account_id":"33333333-3333-4333-8333-333333333333","vault_id":"44444444-4444-4444-8444-444444444444","access_token":"claimed-access-token","access_token_expires_in":900,"refresh_token":"claimed-refresh-token"}'
    else
      status=201
      body='{"account_id":"55555555-5555-4555-8555-555555555555","vault_id":"66666666-6666-4666-8666-666666666666","access_token":"plain-access-token","access_token_expires_in":900,"refresh_token":"plain-refresh-token","recovery_codes":["recovery-secret"]}'
    fi
    ;;
  'GET /v1/account')
    status=200
    body='{"account_id":"redacted","clovery_id":"smoke","status":"active","created_at":"2026-08-01T00:00:00Z","has_password":true,"passkey_count":0,"recovery_codes_remaining":0,"bindings":[{"provider":"apple","issuer":"https://appleid.apple.com","created_at":"2026-08-01T00:00:00Z"}]}'
    ;;
  'GET /v1/account/bootstrap')
    status=200
    if [ "$token" = "plain-access-token" ]; then source=new_install; else source=legacy_local; fi
    body="{\"status\":\"pending\",\"source_kind\":\"$source\",\"migration_id\":null,\"stages\":{\"identity\":\"complete\",\"migration\":\"complete\",\"entitlement\":\"pending\",\"vault\":\"pending\"},\"last_error_code\":null,\"retry_count\":0,\"updated_at\":\"2026-08-01T00:00:00Z\"}"
    ;;
  'POST /v1/vault/sync/push') status=200; body='{"results":[{"status":"applied"}]}' ;;
  'POST /v1/vault/migrations') status=201; body='{"status":"uploading"}' ;;
  POST\ /v1/vault/migrations/*/entries) status=204; body='' ;;
  POST\ /v1/vault/migrations/*/verify|GET\ /v1/vault/migrations/*/report)
    status=200
    case "$path" in
      *a1000000*) body='{"status":"verified","inserted_entries":1,"duplicate_entries":0,"conflict_copies":0}' ;;
      *a2000000*) body='{"status":"verified","inserted_entries":1,"duplicate_entries":1,"conflict_copies":0}' ;;
      *a3000000*) body='{"status":"verified","inserted_entries":1,"duplicate_entries":0,"conflict_copies":1}' ;;
    esac
    ;;
  'POST /v1/billing/apple/legacy-claims')
    if [ "$token" = "other-access-token" ]; then
      status=409
      body='{"code":"apple_transaction_claimed","message":"redacted"}'
    else
      status=200
      body='{"product_id":"com.clovery.app.board.lifetime","state":"active","source_storefront":"apple","source_transaction_id":"transaction-secret","updated_at":"2026-08-01T00:00:00Z"}'
    fi
    ;;
  'GET /v1/account/entitlements')
    status=200
    body='{"entitlements":[{"product_id":"com.clovery.app.board.lifetime","state":"active","source_storefront":"apple","source_transaction_id":"transaction-secret","updated_at":"2026-08-01T00:00:00Z"}]}'
    ;;
esac

[ -z "$output" ] || printf '%s\n' "$body" >"$output"
[ "$write_out" != '%{http_code}' ] || printf '%s' "$status"
EOF
chmod +x "$fake_curl"

run_account_smoke() {
  CLOVERY_API_BASE_URL=https://api.staging.clovery.cn \
  SECURE_EVIDENCE_DIR="$evidence_directory" \
  CURL_BIN="$fake_curl" \
  BOUND_APPLE_COMPLETE_REQUEST_FILE="$evidence_directory/bound-complete.json" \
  BOUND_APPLE_EXPECTED_ROOT_FILE="$evidence_directory/bound-root.json" \
  UNBOUND_APPLE_COMPLETE_REQUEST_FILE="$evidence_directory/unbound-complete.json" \
  CLAIM_REGISTRATION_TEMPLATE_FILE="$evidence_directory/claim-registration.json" \
  CLAIM_REPLAY_REGISTRATION_TEMPLATE_FILE="$evidence_directory/claim-replay.json" \
  PLAIN_REGISTRATION_REQUEST_FILE="$evidence_directory/plain-registration.json" \
  MIGRATION_RETRY_FIXTURE_DIR="$evidence_directory/migration-retry" \
  MIGRATION_CONTENT_DUPLICATE_FIXTURE_DIR="$evidence_directory/migration-duplicate" \
  MIGRATION_ID_CONFLICT_FIXTURE_DIR="$evidence_directory/migration-conflict" \
  "$account_smoke"
}

account_output="$temporary_directory/account-output.txt"
run_account_smoke >"$account_output"

billing_output="$temporary_directory/billing-output.txt"
CLOVERY_API_BASE_URL=https://api.staging.clovery.cn \
SECURE_EVIDENCE_DIR="$evidence_directory" \
CURL_BIN="$fake_curl" \
LEGACY_ENTITLEMENT_PRIMARY_ACCESS_TOKEN_FILE="$evidence_directory/primary.token" \
LEGACY_ENTITLEMENT_OTHER_ACCESS_TOKEN_FILE="$evidence_directory/other.token" \
LEGACY_ENTITLEMENT_SECOND_DEVICE_ACCESS_TOKEN_FILE="$evidence_directory/second-device.token" \
LEGACY_APPLE_CLAIM_REQUEST_FILE="$evidence_directory/legacy-claim.json" \
APPLE_BILLING_PRODUCT_ID=com.clovery.app.board.lifetime \
"$billing_smoke" >"$billing_output"

[ "$(grep -c ': PASS$' "$account_output")" -eq 9 ] || fail "account smoke did not report nine passing scenarios"
[ "$(grep -c ': PASS$' "$billing_output")" -eq 4 ] || fail "billing smoke did not report four passing scenarios"
if grep -Eq 'opaque_claim_token|access-token|refresh-token|transaction-secret|signed-transaction|11111111|33333333' \
  "$account_output" "$billing_output"; then
  fail "smoke output disclosed protected evidence"
fi
if find "$evidence_directory" -maxdepth 1 -type d -name '.ios-1.1.0-smoke.*' -print | grep -q .; then
  fail "smoke scripts left temporary response evidence"
fi

failure_output="$temporary_directory/failure-output.txt"
if FAKE_BOUND_FAILURE=true run_account_smoke >"$failure_output" 2>&1; then
  fail "account smoke unexpectedly passed a server failure"
fi
grep -Fxq 'bound Apple -> original account/vault: FAIL' "$failure_output" || \
  fail "account smoke failure output is not aggregate-only"
if grep -Eq 'must-never-leak|internal_error|debug_token' "$failure_output"; then
  fail "account smoke failure disclosed the response body"
fi

acceptance_runbook="$v2_root/docs/release/ios-1.1.0-staging-acceptance.md"
staging_example="$v2_root/infra/staging/.env.example"
grep -Fq 'bound Apple -> original account/vault | `NOT_RUN`' "$acceptance_runbook" || \
  fail "staging runbook does not keep external identity acceptance open"
grep -Fq 'database write failure/recovery | `NOT_RUN`' "$acceptance_runbook" || \
  fail "staging runbook does not keep failure injection open"
grep -Fq 'IDENTITY_CLAIM_TTL_SECONDS=600' "$staging_example" || fail "staging claim TTL is missing"
grep -Fq 'MIGRATION_WRITES_ENABLED=true' "$staging_example" || fail "staging acceptance writes are disabled"
grep -Fq 'APPLE_BILLING_BUNDLE_ID=com.clovery.app' "$staging_example" || fail "staging bundle ID is missing"
grep -Fq 'APPLE_BILLING_PRODUCT_IDS=com.clovery.app.board.lifetime' "$staging_example" || \
  fail "staging lifetime product is missing"
grep -Fq 'APPLE_SERVER_NOTIFICATION_URL=https://api.staging.clovery.cn/v1/billing/apple/notifications' \
  "$staging_example" || fail "staging Apple notification URL is missing"

echo "iOS 1.1.0 staging smoke contracts passed"
