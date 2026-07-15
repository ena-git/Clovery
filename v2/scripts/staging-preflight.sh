#!/bin/sh

set -eu

v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$v2_root/scripts/lib/staging-env.sh"

usage() {
  echo "usage: staging-preflight.sh ENV_FILE migration|runtime|acceptance" >&2
  exit 2
}

fail() {
  echo "staging preflight failed: $1" >&2
  exit 1
}

[ "$#" -eq 2 ] || usage
environment_file=$1
phase=$2
[ -r "$environment_file" ] || fail "environment file is not readable"

case "$phase" in
  migration|runtime|acceptance) ;;
  *) usage ;;
esac

value_for() {
  key=$1
  count=$(awk -v key="$key" 'index($0, key "=") == 1 { count++ } END { print count + 0 }' "$environment_file")
  [ "$count" -eq 1 ] || fail "$key must appear exactly once"
  awk -v key="$key" 'index($0, key "=") == 1 { print substr($0, length(key) + 2) }' "$environment_file"
}

require_value() {
  key=$1
  value=$(value_for "$key")
  [ -n "$value" ] || fail "$key is required"
  printf '%s' "$value"
}

reject_placeholder() {
  key=$1
  value=$(require_value "$key")
  normalized=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  case "$normalized" in
    *replace*|*change-me*|*changeme*|*clovery_dev_only*|*localhost*|*127.0.0.1*|*.example*|*'<'*|*'>'*)
      fail "$key still contains a development or placeholder value"
      ;;
  esac
}

require_https() {
  key=$1
  value=$(require_value "$key")
  case "$value" in
    https://?*) ;;
    *) fail "$key must use HTTPS" ;;
  esac
}

require_length() {
  key=$1
  minimum=$2
  value=$(require_value "$key")
  [ "${#value}" -ge "$minimum" ] || fail "$key must contain at least $minimum bytes"
}

require_boolean() {
  key=$1
  value=$(require_value "$key")
  case "$value" in
    true|false) ;;
    *) fail "$key must be true or false" ;;
  esac
}

validate_optional_oidc() {
  prefix=$1
  configured=0
  for suffix in CLIENT_ID CLIENT_SECRET REDIRECT_URL; do
    value=$(value_for "${prefix}_OIDC_${suffix}")
    [ -z "$value" ] || configured=$((configured + 1))
  done
  [ "$configured" -eq 0 ] || [ "$configured" -eq 3 ] || fail "${prefix}_OIDC configuration is incomplete"
  if [ "$configured" -eq 3 ]; then
    for suffix in CLIENT_ID CLIENT_SECRET REDIRECT_URL; do
      reject_placeholder "${prefix}_OIDC_${suffix}"
    done
    require_https "${prefix}_OIDC_REDIRECT_URL" >/dev/null
  fi
}

validate_optional_apple_iap() {
  configured=0
  for key in APPLE_IAP_ISSUER_ID APPLE_IAP_KEY_ID APPLE_IAP_PRIVATE_KEY_BASE64 \
    APPLE_IAP_BUNDLE_ID APPLE_IAP_APP_APPLE_ID APPLE_IAP_ROOT_CA_BASE64 \
    APPLE_IAP_PRODUCT_IDS; do
    value=$(value_for "$key")
    [ -z "$value" ] || configured=$((configured + 1))
  done
  [ "$configured" -eq 0 ] || [ "$configured" -eq 7 ] || fail "APPLE_IAP configuration is incomplete"
  if [ "$configured" -eq 7 ]; then
    for key in APPLE_IAP_ISSUER_ID APPLE_IAP_KEY_ID APPLE_IAP_PRIVATE_KEY_BASE64 \
      APPLE_IAP_BUNDLE_ID APPLE_IAP_APP_APPLE_ID APPLE_IAP_ROOT_CA_BASE64 \
      APPLE_IAP_PRODUCT_IDS; do
      reject_placeholder "$key"
    done
    printf '%s\n' "$(value_for APPLE_IAP_APP_APPLE_ID)" | grep -Eq '^[1-9][0-9]+$' || fail "APPLE_IAP_APP_APPLE_ID must be numeric"
  fi
}

[ "$(require_value DEPLOYMENT_ENVIRONMENT)" = "staging" ] || fail "DEPLOYMENT_ENVIRONMENT must be staging"

reject_placeholder CLOVERY_API_IMAGE
image=$(value_for CLOVERY_API_IMAGE)
printf '%s\n' "$image" | grep -Eq '@sha256:[0-9a-f]{64}$' || fail "CLOVERY_API_IMAGE must use an immutable sha256 digest"

release_sha=$(require_value CLOVERY_RELEASE_SHA)
printf '%s\n' "$release_sha" | grep -Eq '^[0-9a-f]{40,64}$' || fail "CLOVERY_RELEASE_SHA must be a full commit SHA"

declared_environment_file=$(require_value CLOVERY_ENV_FILE)
[ -r "$declared_environment_file" ] || fail "CLOVERY_ENV_FILE must point to a readable file"

bind_port=$(require_value CLOVERY_API_BIND_PORT)
printf '%s\n' "$bind_port" | grep -Eq '^[0-9]{1,5}$' || fail "CLOVERY_API_BIND_PORT must be numeric"
[ "$bind_port" -ge 1 ] && [ "$bind_port" -le 65535 ] || fail "CLOVERY_API_BIND_PORT is outside the valid range"

database_url=$(require_value DATABASE_URL)
case "$database_url" in
  postgres://?*/*|postgresql://?*/*) ;;
  *) fail "DATABASE_URL must use PostgreSQL" ;;
esac
staging_database_requires_tls "$database_url" || fail "DATABASE_URL must require TLS"
reject_placeholder DATABASE_URL

require_https S3_ENDPOINT >/dev/null
reject_placeholder S3_ENDPOINT
reject_placeholder S3_BUCKET
reject_placeholder S3_ACCESS_KEY
reject_placeholder S3_SECRET_KEY
[ "$(require_value S3_ALLOW_INSECURE)" = "false" ] || fail "S3_ALLOW_INSECURE must be false"

require_https JWT_ISSUER >/dev/null
reject_placeholder JWT_ISSUER
require_length JWT_SIGNING_KEY 32 >/dev/null
reject_placeholder JWT_SIGNING_KEY
reject_placeholder WEBAUTHN_RP_ID
reject_placeholder WEBAUTHN_RP_DISPLAY_NAME
require_https WEBAUTHN_RP_ORIGINS >/dev/null
reject_placeholder WEBAUTHN_RP_ORIGINS

passkey_key=$(require_value PASSKEY_CREDENTIAL_ENCRYPTION_KEY)
printf '%s\n' "$passkey_key" | grep -Eq '^[A-Za-z0-9+/]{43}=$' || fail "PASSKEY_CREDENTIAL_ENCRYPTION_KEY must encode exactly 32 bytes"
[ "$passkey_key" != "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=" ] || fail "PASSKEY_CREDENTIAL_ENCRYPTION_KEY must not use the development key"

require_length METRICS_BEARER_TOKEN 32 >/dev/null
reject_placeholder METRICS_BEARER_TOKEN
[ "$(require_value PORT)" = "8080" ] || fail "PORT must remain 8080 inside the container"
require_boolean MIGRATION_WRITES_ENABLED
require_boolean APPLE_IAP_ALLOW_SANDBOX

for provider in APPLE GOOGLE HUAWEI; do
  validate_optional_oidc "$provider"
done
validate_optional_apple_iap

case "$phase" in
  migration)
    [ "$(value_for MIGRATION_WRITES_ENABLED)" = "false" ] || fail "migration phase requires MIGRATION_WRITES_ENABLED=false"
    ;;
  acceptance)
    [ "$(value_for MIGRATION_WRITES_ENABLED)" = "true" ] || fail "acceptance phase requires MIGRATION_WRITES_ENABLED=true"
    for provider in APPLE GOOGLE HUAWEI; do
      [ -n "$(value_for "${provider}_OIDC_CLIENT_ID")" ] || fail "${provider}_OIDC is required for acceptance"
    done
    [ -n "$(value_for APPLE_IAP_ISSUER_ID)" ] || fail "APPLE_IAP is required for acceptance"
    [ "$(value_for APPLE_IAP_BUNDLE_ID)" = "com.clovery.app" ] || fail "APPLE_IAP_BUNDLE_ID must preserve com.clovery.app"
    case "$(value_for APPLE_IAP_PRODUCT_IDS)" in
      *com.clovery.app.board.lifetime*) ;;
      *) fail "APPLE_IAP_PRODUCT_IDS must include the existing lifetime product" ;;
    esac
    [ "$(value_for APPLE_IAP_ALLOW_SANDBOX)" = "true" ] || fail "staging acceptance requires Apple sandbox validation"
    ;;
esac

echo "staging preflight passed for $phase phase"
