#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
checker="$repository_root/scripts/verify-repository-hygiene.sh"
rules="$repository_root/scripts/lib/repository-hygiene-rules.sh"

for executable in "$checker" "$rules"; do
  if [ ! -x "$executable" ]; then
    echo "missing executable repository hygiene helper: $executable" >&2
    exit 1
  fi
done

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/clovery-repository-hygiene.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
probe_output="$temporary_directory/probe-output.txt"

new_fixture() {
  name=$1
  fixture="$temporary_directory/$name"
  mkdir -p "$fixture/scripts/lib" "$fixture/Tests"
  cp "$checker" "$fixture/scripts/verify-repository-hygiene.sh"
  cp "$rules" "$fixture/scripts/lib/repository-hygiene-rules.sh"
  chmod +x \
    "$fixture/scripts/verify-repository-hygiene.sh" \
    "$fixture/scripts/lib/repository-hygiene-rules.sh"
  printf '%s\n' 'source' > "$fixture/source.txt"
  printf '%s\n' '/build/' '*.xcresult' '*.xcarchive' > "$fixture/.gitignore"
  git -C "$fixture" init -q
  git -C "$fixture" add .
  git -C "$fixture" -c user.name=Clovery -c user.email=fixture@invalid.local \
    commit -qm baseline
  printf '%s\n' "$fixture"
}

expect_failure() {
  label=$1
  fixture=$2
  shift 2
  if (cd "$fixture" && "$@") > "$probe_output" 2>&1; then
    echo "repository hygiene probe unexpectedly passed: $label" >&2
    exit 1
  fi
}

expect_success() {
  label=$1
  fixture=$2
  shift 2
  if ! (cd "$fixture" && "$@") > "$probe_output" 2>&1; then
    echo "repository hygiene probe failed: $label" >&2
    cat "$probe_output" >&2
    exit 1
  fi
}

fixture=$(new_fixture clean)
expect_success "clean repository" "$fixture" scripts/verify-repository-hygiene.sh

fixture=$(new_fixture environment)
printf '%s\n' 'DATABASE_URL=secret' > "$fixture/.env"
git -C "$fixture" add -f .env
expect_failure "tracked environment file" "$fixture" scripts/verify-repository-hygiene.sh

fixture=$(new_fixture signing)
printf '%s\n' 'private signing key' > "$fixture/AuthKey_TEST.p8"
git -C "$fixture" add AuthKey_TEST.p8
expect_failure "tracked signing key" "$fixture" scripts/verify-repository-hygiene.sh

fixture=$(new_fixture api-key)
printf 'AKIA%s%s\n' 'ABCDEFGH' 'IJKLMNOP' > "$fixture/config.txt"
git -C "$fixture" add config.txt
expect_failure "tracked API key" "$fixture" scripts/verify-repository-hygiene.sh

fixture=$(new_fixture migration)
mkdir -p "$fixture/Documents/CloveryMigration"
printf '%s\n' 'private diary export' > "$fixture/Documents/CloveryMigration/user.cloverymigration"
git -C "$fixture" add -f Documents/CloveryMigration/user.cloverymigration
expect_failure "tracked migration bundle" "$fixture" scripts/verify-repository-hygiene.sh

fixture=$(new_fixture generated)
mkdir -p "$fixture/scratch/build"
dd if=/dev/zero of="$fixture/scratch/build/cache.bin" bs=1024 count=24 >/dev/null 2>&1
expect_failure "unignored generated directory" "$fixture" \
  env CLOVERY_HYGIENE_GENERATED_LIMIT_KB=16 scripts/verify-repository-hygiene.sh

fixture=$(new_fixture generated-status)
mkdir -p "$fixture/scratch/DerivedData"
printf '%s\n' 'small generated output' > "$fixture/scratch/DerivedData/cache.txt"
expect_failure "generated output in git status" "$fixture" \
  scripts/verify-repository-hygiene.sh

fixture=$(new_fixture large-file)
dd if=/dev/zero of="$fixture/large.bin" bs=1024 count=30 >/dev/null 2>&1
git -C "$fixture" add large.bin
expect_failure "unreviewed tracked large file" "$fixture" \
  env CLOVERY_HYGIENE_TRACKED_LIMIT_BYTES=20480 scripts/verify-repository-hygiene.sh

fixture=$(new_fixture allowed-static)
mkdir -p "$fixture/Clovery"
dd if=/dev/zero of="$fixture/Clovery/Clover Diary.html" bs=1024 count=30 >/dev/null 2>&1
git -C "$fixture" add 'Clovery/Clover Diary.html'
expect_success "reviewed static web asset" "$fixture" \
  env CLOVERY_HYGIENE_TRACKED_LIMIT_BYTES=20480 scripts/verify-repository-hygiene.sh

fixture=$(new_fixture evidence-email)
mkdir -p "$fixture/docs/superpowers/verification"
printf '%s\n' 'Tester email: real-user@example.com' \
  > "$fixture/docs/superpowers/verification/result.md"
git -C "$fixture" add docs/superpowers/verification/result.md
expect_failure "release evidence email" "$fixture" scripts/verify-repository-hygiene.sh

fixture=$(new_fixture evidence-id)
mkdir -p "$fixture/docs/release"
printf '%s\n' 'Account: 11111111-1111-4111-8111-111111111111' \
  > "$fixture/docs/release/ios-acceptance.md"
git -C "$fixture" add docs/release/ios-acceptance.md
expect_failure "release evidence account UUID" "$fixture" scripts/verify-repository-hygiene.sh

fixture=$(new_fixture evidence-sha)
mkdir -p "$fixture/docs/superpowers/verification"
printf '%s\n' 'Tested commit: 0123456789abcdef0123456789abcdef01234567' \
  > "$fixture/docs/superpowers/verification/result.md"
git -C "$fixture" add docs/superpowers/verification/result.md
expect_failure "release evidence full commit SHA" "$fixture" scripts/verify-repository-hygiene.sh

fixture=$(new_fixture evidence-recovery)
mkdir -p "$fixture/docs/release"
printf '%s\n' 'Recovery code: ABCD-EFGH-IJKL-MNOP' \
  > "$fixture/docs/release/ios-acceptance.md"
git -C "$fixture" add docs/release/ios-acceptance.md
expect_failure "release evidence recovery code" "$fixture" scripts/verify-repository-hygiene.sh

echo "repository hygiene negative probes verified"
