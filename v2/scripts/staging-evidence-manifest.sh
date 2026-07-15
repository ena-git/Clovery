#!/bin/sh

set -eu
umask 077

v2_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$v2_root/scripts/lib/staging-env.sh"
. "$v2_root/scripts/lib/staging-checksum.sh"
. "$v2_root/scripts/lib/staging-path.sh"

fail() {
  echo "staging evidence manifest failed: $1" >&2
  exit 1
}

[ "$#" -eq 5 ] || fail "usage: staging-evidence-manifest.sh ENV_FILE BACKUP_DIRECTORY RESTORE_EVIDENCE SMOKE_EVIDENCE EVIDENCE_ROOT"
environment_file=$1
backup_directory=$2
restore_evidence=$3
smoke_evidence=$4
evidence_root=$5
repository_root=$(CDPATH= cd -- "$v2_root/.." && pwd -P)

"$v2_root/scripts/staging-preflight.sh" "$environment_file" runtime >/dev/null
backup_directory=$(staging_external_directory "$backup_directory" "$repository_root") || \
  fail "backup directory must be outside the Git repository"
evidence_root=$(staging_external_directory "$evidence_root" "$repository_root") || \
  fail "evidence root must be an existing directory outside the Git repository"
release_sha=$(staging_env_require "$environment_file" CLOVERY_RELEASE_SHA) || exit 1
api_image=$(staging_env_require "$environment_file" CLOVERY_API_IMAGE) || exit 1
image_digest=${api_image##*@}

backup_metadata="$backup_directory/metadata.env"
dump_path="$backup_directory/database.dump"
checksum_path="$backup_directory/database.dump.sha256"
for required_file in "$backup_metadata" "$dump_path" "$checksum_path" "$restore_evidence" "$smoke_evidence"; do
  [ -r "$required_file" ] || fail "required evidence file is missing"
done

backup_release_sha=$(staging_env_require "$backup_metadata" release_sha) || exit 1
restore_release_sha=$(staging_env_require "$restore_evidence" release_sha) || exit 1
smoke_release_sha=$(staging_env_require "$smoke_evidence" release_sha) || exit 1
for evidence_release_sha in "$backup_release_sha" "$restore_release_sha" "$smoke_release_sha"; do
  [ "$evidence_release_sha" = "$release_sha" ] || fail "evidence release SHA does not match the deployment"
done
smoke_image_digest=$(staging_env_require "$smoke_evidence" image_digest) || exit 1
[ "$smoke_image_digest" = "$image_digest" ] || fail "smoke evidence image digest does not match the deployment"

expected_dump_sha256=$(awk 'NR == 1 { print $1 }' "$checksum_path")
actual_dump_sha256=$(staging_sha256 "$dump_path")
[ "$expected_dump_sha256" = "$actual_dump_sha256" ] || fail "backup dump checksum does not match"

restore_dump_sha256=$(staging_env_require "$restore_evidence" dump_sha256) || exit 1
[ "$restore_dump_sha256" = "$actual_dump_sha256" ] || fail "restore drill used a different backup dump"

backup_metadata_sha256=$(staging_sha256 "$backup_metadata")
restore_evidence_sha256=$(staging_sha256 "$restore_evidence")
smoke_evidence_sha256=$(staging_sha256 "$smoke_evidence")
backup_id=$(basename "${backup_directory%/}")
restore_evidence_id=$(basename "$restore_evidence")
smoke_evidence_id=$(basename "$smoke_evidence")
created_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
directory_stamp=$(date -u '+%Y%m%dT%H%M%SZ')
short_sha=$(printf '%s' "$release_sha" | cut -c1-12)

chmod 700 "$evidence_root"
manifest_path="$evidence_root/release-evidence-$directory_stamp-$short_sha.env"
[ ! -e "$manifest_path" ] || fail "release evidence destination already exists"
pending_manifest=$(mktemp "$evidence_root/.release-evidence.XXXXXX")

cat >"$pending_manifest" <<EOF
release_evidence_format=1
created_at=$created_at
release_sha=$release_sha
image_digest=$image_digest
backup_id=$backup_id
backup_dump_sha256=$actual_dump_sha256
backup_metadata_sha256=$backup_metadata_sha256
restore_evidence_id=$restore_evidence_id
restore_evidence_sha256=$restore_evidence_sha256
smoke_evidence_id=$smoke_evidence_id
smoke_evidence_sha256=$smoke_evidence_sha256
EOF
chmod 600 "$pending_manifest"
mv "$pending_manifest" "$manifest_path"

printf '%s\n' "$manifest_path"
