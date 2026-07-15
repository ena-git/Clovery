#!/bin/sh

set -eu
umask 077

v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$v2_root/scripts/lib/staging-env.sh"
. "$v2_root/scripts/lib/staging-checksum.sh"
. "$v2_root/scripts/lib/staging-path.sh"

fail() {
  echo "staging smoke failed: $1" >&2
  exit 1
}

[ "$#" -eq 3 ] || fail "usage: staging-smoke.sh ENV_FILE API_BASE_URL EVIDENCE_ROOT"
environment_file=$1
api_base_url=${2%/}
evidence_root=$3
repository_root=$(CDPATH= cd -- "$v2_root/.." && pwd -P)

"$v2_root/scripts/staging-preflight.sh" "$environment_file" runtime >/dev/null
evidence_root=$(staging_external_directory "$evidence_root" "$repository_root") || \
  fail "evidence root must be an existing directory outside the Git repository"
case "$api_base_url" in
  https://*) ;;
  *) fail "API_BASE_URL must use HTTPS" ;;
esac

release_sha=$(staging_env_require "$environment_file" CLOVERY_RELEASE_SHA) || exit 1
api_image=$(staging_env_require "$environment_file" CLOVERY_API_IMAGE) || exit 1
image_digest=${api_image##*@}
metrics_token=$(staging_env_require "$environment_file" METRICS_BEARER_TOKEN) || exit 1
curl_bin=${CURL_BIN:-curl}
command -v "$curl_bin" >/dev/null 2>&1 || fail "curl is unavailable"

health_body=$(mktemp "${TMPDIR:-/tmp}/clovery-health.XXXXXX")
metrics_unauthorized_body=$(mktemp "${TMPDIR:-/tmp}/clovery-metrics-unauthorized.XXXXXX")
metrics_authorized_body=$(mktemp "${TMPDIR:-/tmp}/clovery-metrics-authorized.XXXXXX")
metrics_header=$(mktemp "${TMPDIR:-/tmp}/clovery-metrics-header.XXXXXX")
trap 'rm -f "$health_body" "$metrics_unauthorized_body" "$metrics_authorized_body" "$metrics_header"' EXIT HUP INT TERM
printf 'Authorization: Bearer %s\n' "$metrics_token" >"$metrics_header"

health_status=$("$curl_bin" -sS -o "$health_body" -w '%{http_code}' \
  --connect-timeout 5 --max-time 15 "$api_base_url/v1/health")
[ "$health_status" = "200" ] || fail "health endpoint returned HTTP $health_status"
grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"' "$health_body" || fail "health payload does not report ok"
grep -Eq '"service"[[:space:]]*:[[:space:]]*"clovery-api"' "$health_body" || fail "health payload reports the wrong service"

metrics_unauthorized_status=$("$curl_bin" -sS -o "$metrics_unauthorized_body" -w '%{http_code}' \
  --connect-timeout 5 --max-time 15 "$api_base_url/internal/metrics")
[ "$metrics_unauthorized_status" = "401" ] || fail "metrics endpoint is not bearer-protected"

metrics_authorized_status=$("$curl_bin" -sS -o "$metrics_authorized_body" -w '%{http_code}' \
  --connect-timeout 5 --max-time 15 -H "@$metrics_header" \
  "$api_base_url/internal/metrics")
[ "$metrics_authorized_status" = "200" ] || fail "authorized metrics request returned HTTP $metrics_authorized_status"
grep -Fq '# TYPE clovery_' "$metrics_authorized_body" || fail "metrics payload is not the Clovery registry"

health_sha256=$(staging_sha256 "$health_body")
metrics_sha256=$(staging_sha256 "$metrics_authorized_body")
created_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
directory_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
short_sha=$(printf '%s' "$release_sha" | cut -c1-12)

chmod 700 "$evidence_root"
evidence_path="$evidence_root/smoke-$directory_stamp-$short_sha.env"
[ ! -e "$evidence_path" ] || fail "smoke evidence destination already exists"
pending_evidence=$(mktemp "$evidence_root/.smoke.XXXXXX")

cat >"$pending_evidence" <<EOF
smoke_evidence_format=1
created_at=$created_at
release_sha=$release_sha
image_digest=$image_digest
health_status=$health_status
metrics_unauthorized_status=$metrics_unauthorized_status
metrics_authorized_status=$metrics_authorized_status
health_payload_sha256=$health_sha256
metrics_payload_sha256=$metrics_sha256
EOF
chmod 600 "$pending_evidence"
mv "$pending_evidence" "$evidence_path"

printf '%s\n' "$evidence_path"
