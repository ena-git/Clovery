#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
verification_script="$repository_root/scripts/verify-ios-1.1.0.sh"
verification_library="$repository_root/scripts/lib/ios-release-verification.sh"
legacy_entrypoint="$repository_root/scripts/verify-ios-v1.sh"
workflow="$repository_root/.github/workflows/verify-ios-v1.yml"

require_text() {
  file=$1
  expected=$2
  label=$3
  if ! grep -Fq "$expected" "$file"; then
    echo "$label missing from $file" >&2
    exit 1
  fi
}

require_absent() {
  file=$1
  unexpected=$2
  label=$3
  if grep -Fq "$unexpected" "$file"; then
    echo "$label must not appear in $file" >&2
    exit 1
  fi
}

if [ ! -x "$verification_script" ]; then
  echo "iOS 1.1.0 verification entrypoint must exist and be executable" >&2
  exit 1
fi

if [ ! -f "$verification_library" ]; then
  echo "modular iOS release verification library must exist" >&2
  exit 1
fi

require_text "$verification_library" 'https://api.clovery.cn' "production API lock"
require_text "$verification_library" 'mktemp -d /private/tmp/clovery-ios-1.1.0.' "private temporary root"
require_text "$verification_library" 'trap cleanup EXIT HUP INT TERM' "temporary cleanup"
require_text "$verification_library" 'go test -race ./...' "backend race gate"
require_text "$verification_library" 'go build -o "$verification_root/clovery-api" ./cmd/api' "temporary backend binary"
require_text "$verification_library" 'test-ios-1.1.0-staging-smoke.sh' "staging smoke contract gate"
require_text "$verification_library" 'validate-v1-html.cjs' "HTML gate"
require_text "$verification_library" 'test-v1-p0-contract.sh' "P0 bridge contract gate"
require_text "$verification_library" 'test-v1-bridge.sh' "Swift bridge gate"
require_text "$verification_library" 'test-migration-zip.sh' "migration ZIP gate"
require_text "$verification_library" 'IOSReleaseIdentityTests.sh' "release identity gate"
require_text "$verification_library" 'RepositoryHygieneTests.sh' "repository hygiene probe gate"
require_text "$verification_library" 'verify-repository-hygiene.sh' "repository hygiene gate"
require_text "$verification_library" 'resultBundlePath' "XCTest result bundle"
require_text "$verification_library" "generic/platform=iOS Simulator" "Release simulator build"
require_text "$verification_library" 'CODE_SIGNING_ALLOWED=NO' "unsigned simulator build"
require_absent "$verification_library" 'build/DerivedData' "repository-local DerivedData"

require_text "$legacy_entrypoint" 'exec "$repository_root/scripts/verify-ios-1.1.0.sh" "$@"' "legacy delegation"
require_text "$workflow" 'run: scripts/verify-ios-1.1.0.sh' "CI verification entrypoint"
require_absent "$workflow" 'run: scripts/verify-ios-v1.sh' "obsolete CI entrypoint"

probe_root=$(mktemp -d)
trap 'rm -rf "$probe_root"' EXIT HUP INT TERM
set +e
probe_output=$(
  VERIFICATION_LIBRARY="$verification_library" PROBE_ROOT="$probe_root" sh -c '
    set -eu
    . "$VERIFICATION_LIBRARY"
    verification_root="$PROBE_ROOT"
    verification_summary="$verification_root/summary.txt"
    : >"$verification_summary"
    failing_gate() {
      echo "private diagnostic payload"
      return 23
    }
    run_gate "Failure probe" failure-probe failing_gate
  ' 2>&1
)
probe_status=$?
set -e

if [ "$probe_status" -ne 23 ]; then
  echo "failed verification gate must preserve its exit status" >&2
  exit 1
fi
if printf '%s\n' "$probe_output" | grep -Fq "private diagnostic payload"; then
  echo "failed verification gate must not print raw command output" >&2
  exit 1
fi
if ! printf '%s\n' "$probe_output" | grep -Fq "Failure probe: FAIL (exit 23)"; then
  echo "failed verification gate must print a redacted failure summary" >&2
  exit 1
fi

echo "iOS 1.1.0 verification script contract verified"
