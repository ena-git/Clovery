#!/bin/sh

set -eu

v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
smoke_script="$v2_root/scripts/staging-smoke.sh"
manifest_script="$v2_root/scripts/staging-evidence-manifest.sh"
fixture="$v2_root/scripts/testlib/staging-fixture.sh"
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/clovery-staging-smoke.XXXXXX")
repository_evidence_root="$v2_root/.staging-evidence-test-$$"
trap 'rm -rf "$temporary_directory" "$repository_evidence_root"' EXIT HUP INT TERM

. "$fixture"
. "$v2_root/scripts/lib/staging-checksum.sh"

fail() {
  echo "staging smoke-evidence test failed: $1" >&2
  exit 1
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

[ -x "$smoke_script" ] || fail "missing executable staging-smoke.sh"
[ -x "$manifest_script" ] || fail "missing executable staging-evidence-manifest.sh"

environment_file="$temporary_directory/staging.env"
write_staging_environment_fixture "$environment_file"

fake_curl="$temporary_directory/fake-curl"
cat >"$fake_curl" <<'EOF'
#!/bin/sh
set -eu
output=
write_out=
authorization=false
url=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) output=$2; shift 2 ;;
    -w) write_out=$2; shift 2 ;;
    -H)
      case "$2" in Authorization:*|@*) authorization=true ;; esac
      shift 2
      ;;
    -s|-S|-sS|--connect-timeout|--max-time)
      case "$1" in --connect-timeout|--max-time) shift 2 ;; *) shift ;; esac
      ;;
    *) url=$1; shift ;;
  esac
done

case "$url" in
  */v1/health)
    status=${FAKE_HEALTH_STATUS:-200}
    body='{"status":"ok","service":"clovery-api"}'
    ;;
  */internal/metrics)
    if [ "$authorization" = true ]; then
      status=200
      body='# TYPE clovery_auth_login_failed_total counter'
    else
      status=401
      body='unauthorized'
    fi
    ;;
  *) status=404; body='not found' ;;
esac

[ -z "$output" ] || printf '%s\n' "$body" >"$output"
[ "$write_out" != '%{http_code}' ] || printf '%s' "$status"
EOF
chmod +x "$fake_curl"

mkdir -p "$repository_evidence_root"
expect_failure env CURL_BIN="$fake_curl" \
  "$smoke_script" "$environment_file" https://api.staging.clovery.cn "$repository_evidence_root"

evidence_root="$temporary_directory/evidence"
mkdir -p "$evidence_root"
smoke_evidence=$(CURL_BIN="$fake_curl" \
  "$smoke_script" "$environment_file" https://api.staging.clovery.cn "$evidence_root")

[ -f "$smoke_evidence" ] || fail "smoke evidence is missing"
grep -Fq 'health_status=200' "$smoke_evidence" || fail "health status was not recorded"
grep -Fq 'metrics_unauthorized_status=401' "$smoke_evidence" || fail "metrics protection was not recorded"
grep -Fq 'metrics_authorized_status=200' "$smoke_evidence" || fail "authorized metrics status was not recorded"
grep -Fq 'image_digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  "$smoke_evidence" || fail "deployed image digest was not recorded"
if grep -Eq 'staging-metrics-token|api\.staging\.clovery\.cn' "$smoke_evidence"; then
  fail "smoke evidence contains a token or endpoint"
fi

if FAKE_HEALTH_STATUS=503 CURL_BIN="$fake_curl" \
  "$smoke_script" "$environment_file" https://api.staging.clovery.cn "$evidence_root" \
  >/dev/null 2>&1; then
  fail "unhealthy API unexpectedly passed smoke validation"
fi

backup_directory="$temporary_directory/backup-001"
mkdir -p "$backup_directory"
printf 'database-dump' >"$backup_directory/database.dump"
dump_sha256=$(staging_sha256 "$backup_directory/database.dump")
printf '%s  database.dump\n' "$dump_sha256" >"$backup_directory/database.dump.sha256"
cat >"$backup_directory/metadata.env" <<EOF
backup_format=1
release_sha=5265c62b03b8e53fbe6ebb10c50d5d5d402cef42
dump_sha256=$dump_sha256
EOF
restore_evidence="$backup_directory/restore-evidence-20260715T000000Z.env"
cat >"$restore_evidence" <<EOF
restore_evidence_format=1
release_sha=5265c62b03b8e53fbe6ebb10c50d5d5d402cef42
restore_database=clovery_restore
dump_sha256=$dump_sha256
integrity_json={"accounts":2,"vaults":2}
EOF

manifest=$("$manifest_script" "$environment_file" "$backup_directory" \
  "$restore_evidence" "$smoke_evidence" "$evidence_root")
[ -f "$manifest" ] || fail "release evidence manifest is missing"
grep -Fq 'release_sha=5265c62b03b8e53fbe6ebb10c50d5d5d402cef42' "$manifest" || fail "release SHA is missing"
grep -Fq 'backup_id=backup-001' "$manifest" || fail "backup ID is missing"
grep -Fq 'image_digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  "$manifest" || fail "release image digest is missing"
if grep -Eq 'strong-password|staging-metrics-token|api\.staging\.clovery\.cn' "$manifest"; then
  fail "release evidence manifest contains sensitive configuration"
fi

mismatched_smoke="$temporary_directory/mismatched-smoke.env"
sed 's/5265c62b03b8e53fbe6ebb10c50d5d5d402cef42/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/' \
  "$smoke_evidence" >"$mismatched_smoke"
expect_failure "$manifest_script" "$environment_file" "$backup_directory" \
  "$restore_evidence" "$mismatched_smoke" "$evidence_root"

echo "staging smoke and release evidence verified"
