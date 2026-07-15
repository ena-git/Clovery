#!/bin/sh

set -eu

v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
preflight="$v2_root/scripts/staging-preflight.sh"
compose_file="$v2_root/infra/staging/compose.yaml"
fixture="$v2_root/scripts/testlib/staging-fixture.sh"
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/clovery-staging-config.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

. "$fixture"

fail() {
  echo "staging configuration test failed: $1" >&2
  exit 1
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

valid_environment="$temporary_directory/staging.env"
write_staging_environment_fixture "$valid_environment"

[ -x "$preflight" ] || fail "missing executable staging-preflight.sh"
[ -f "$compose_file" ] || fail "missing staging compose.yaml"

"$preflight" "$valid_environment" migration >/dev/null
"$preflight" "$valid_environment" runtime >/dev/null
expect_failure "$preflight" "$valid_environment" acceptance

acceptance_environment="$temporary_directory/acceptance.env"
sed \
  -e 's|^APPLE_OIDC_CLIENT_ID=$|APPLE_OIDC_CLIENT_ID=com.clovery.app|' \
  -e 's|^APPLE_OIDC_CLIENT_SECRET=$|APPLE_OIDC_CLIENT_SECRET=apple-client-secret|' \
  -e 's|^APPLE_OIDC_REDIRECT_URL=$|APPLE_OIDC_REDIRECT_URL=https://staging.clovery.cn/auth/apple/callback|' \
  -e 's|^GOOGLE_OIDC_CLIENT_ID=$|GOOGLE_OIDC_CLIENT_ID=google-client-id|' \
  -e 's|^GOOGLE_OIDC_CLIENT_SECRET=$|GOOGLE_OIDC_CLIENT_SECRET=google-client-secret|' \
  -e 's|^GOOGLE_OIDC_REDIRECT_URL=$|GOOGLE_OIDC_REDIRECT_URL=https://staging.clovery.cn/auth/google/callback|' \
  -e 's|^HUAWEI_OIDC_CLIENT_ID=$|HUAWEI_OIDC_CLIENT_ID=huawei-client-id|' \
  -e 's|^HUAWEI_OIDC_CLIENT_SECRET=$|HUAWEI_OIDC_CLIENT_SECRET=huawei-client-secret|' \
  -e 's|^HUAWEI_OIDC_REDIRECT_URL=$|HUAWEI_OIDC_REDIRECT_URL=https://staging.clovery.cn/auth/huawei/callback|' \
  -e 's|^APPLE_IAP_ISSUER_ID=$|APPLE_IAP_ISSUER_ID=issuer-id|' \
  -e 's|^APPLE_IAP_KEY_ID=$|APPLE_IAP_KEY_ID=key-id|' \
  -e 's|^APPLE_IAP_PRIVATE_KEY_BASE64=$|APPLE_IAP_PRIVATE_KEY_BASE64=cHJpdmF0ZS1rZXk=|' \
  -e 's|^APPLE_IAP_BUNDLE_ID=$|APPLE_IAP_BUNDLE_ID=com.clovery.app|' \
  -e 's|^APPLE_IAP_APP_APPLE_ID=$|APPLE_IAP_APP_APPLE_ID=1234567890|' \
  -e 's|^APPLE_IAP_ROOT_CA_BASE64=$|APPLE_IAP_ROOT_CA_BASE64=cm9vdC1jYQ==|' \
  -e 's|^APPLE_IAP_PRODUCT_IDS=$|APPLE_IAP_PRODUCT_IDS=com.clovery.app.board.lifetime|' \
  -e 's|^MIGRATION_WRITES_ENABLED=false$|MIGRATION_WRITES_ENABLED=true|' \
  "$valid_environment" >"$acceptance_environment"
sed "s|^CLOVERY_ENV_FILE=.*$|CLOVERY_ENV_FILE=$acceptance_environment|" \
  "$acceptance_environment" >"$acceptance_environment.updated"
mv "$acceptance_environment.updated" "$acceptance_environment"
"$preflight" "$acceptance_environment" acceptance >/dev/null

unsafe_environment="$temporary_directory/unsafe.env"
sed 's/DEPLOYMENT_ENVIRONMENT=staging/DEPLOYMENT_ENVIRONMENT=production/' \
  "$valid_environment" >"$unsafe_environment"
expect_failure "$preflight" "$unsafe_environment" migration

writes_environment="$temporary_directory/writes.env"
sed 's/MIGRATION_WRITES_ENABLED=false/MIGRATION_WRITES_ENABLED=true/' \
  "$valid_environment" >"$writes_environment"
expect_failure "$preflight" "$writes_environment" migration

tls_bypass_environment="$temporary_directory/tls-bypass.env"
sed \
  -e 's/sslmode=verify-full/sslmode=disable\&note=sslmode=require/' \
  -e "s|^CLOVERY_ENV_FILE=.*$|CLOVERY_ENV_FILE=$tls_bypass_environment|" \
  "$valid_environment" >"$tls_bypass_environment"
expect_failure "$preflight" "$tls_bypass_environment" runtime

placeholder_oidc_environment="$temporary_directory/placeholder-oidc.env"
sed \
  -e 's|^APPLE_OIDC_CLIENT_ID=$|APPLE_OIDC_CLIENT_ID=replace-client-id|' \
  -e 's|^APPLE_OIDC_CLIENT_SECRET=$|APPLE_OIDC_CLIENT_SECRET=replace-client-secret|' \
  -e 's|^APPLE_OIDC_REDIRECT_URL=$|APPLE_OIDC_REDIRECT_URL=https://provider.example/callback|' \
  -e "s|^CLOVERY_ENV_FILE=.*$|CLOVERY_ENV_FILE=$placeholder_oidc_environment|" \
  "$valid_environment" >"$placeholder_oidc_environment"
expect_failure "$preflight" "$placeholder_oidc_environment" runtime

placeholder_origin_environment="$temporary_directory/placeholder-origin.env"
sed \
  -e 's|WEBAUTHN_RP_ORIGINS=https://staging.clovery.cn|WEBAUTHN_RP_ORIGINS=https://rp.example|' \
  -e "s|^CLOVERY_ENV_FILE=.*$|CLOVERY_ENV_FILE=$placeholder_origin_environment|" \
  "$valid_environment" >"$placeholder_origin_environment"
expect_failure "$preflight" "$placeholder_origin_environment" runtime

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  rendered_compose="$temporary_directory/compose.rendered.yaml"
  docker compose --env-file "$valid_environment" -f "$compose_file" --profile migration config \
    >"$rendered_compose"
  grep -Fq 'name: clovery-staging' "$rendered_compose" || fail "staging project name is not isolated"
  grep -Fq 'migrate:' "$rendered_compose" || fail "migration job is missing"
  grep -Fq 'api:' "$rendered_compose" || fail "API service is missing"
  if grep -Eq 'postgres-data|minio-data|clovery-v2' "$rendered_compose"; then
    fail "staging compose references development volumes"
  fi
fi

echo "staging configuration contract verified"
