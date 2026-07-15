# Backend Acceptance — 2026-07-15

## Accepted scope

- Clovery root-account authentication, session rotation, recovery, provider binding, device revocation, account deletion requests, and Vault authorization boundaries.
- Journal sync, conflict/tombstone handling, private asset tickets, V1 migration APIs, server-side Apple entitlement ledger, notification replay, metrics, and incident runbooks.
- Forward-only production migration workflow through `000015_migration_source_entry_ids`.
- V1 IDs such as `new-<timestamp>` are retained as `source_entry_id` and deterministically mapped to a Vault-scoped UUID. UUID source IDs remain unchanged.
- Migration manifests bind raw entry/deletion files, each canonical active entry, deleted source IDs, photos, counts, and exact byte totals.

## Automated evidence

- `go test -count=1 ./...`
- `go test -race -count=1 ./internal/sync ./internal/migration ./internal/billing ./internal/http`
- `go vet ./...`
- API and Apple notification replay binaries built successfully.
- Isolated PostgreSQL 16 acceptance passed for repeatable migrations, one-step rollback/reapply, concurrent sync, active and deleted V1 imports, manifest mismatch rejection, purchase-chain ownership, stale notification ordering, legacy purchase records, and billing grace periods.
- iOS Simulator tests passed for the existing app bridge, photo store, migration ZIP export, exact manifest hashes, duplicate/overlap rejection, and tampered-entry rejection.
- Staging configuration, backup/restore safety, API smoke, and release-evidence scripts pass local contract tests through `make verify-staging`.

## Data-safety result

- Existing V1 local data, previous migration archives, Docker PostgreSQL volume, and MinIO volume were not deleted or rewritten.
- Migration remains copy-only until server verification succeeds.
- Older weak migration manifests are retained as backups but cannot be reported as verified; regenerate a strong bundle from the unchanged V1 data before upload.
- Staging Compose declares no database or object-store volumes. Backup and evidence scripts reject any destination inside the Git repository and restore drills reject the source database or a target without the guarded `_restore` suffix.

## External release gates still open

- Provision the managed staging PostgreSQL source/restore databases, private S3 bucket, immutable API image, HTTPS hostname, and secret-manager values; no real cloud resource has been created by the repository-only work.
- Run the conditional-PUT integration test from `backend-deployment.md` against a healthy disposable S3/MinIO environment. The current local Docker VM reports image/data I/O errors, so it is not accepted as object-store evidence.
- Complete staging provider verification for Apple, Google, Huawei, Passkey, recent reauthentication, binding, unbinding, and revoked-device refresh rejection.
- Complete client API smoke tests after the front-end screens and Flutter repositories are available.
- Complete production-like App Store notification, purchase, restore, refund, and legacy-claim checks with App Store Connect configuration.
- Keep real-device testing deferred until the iOS experience is complete and before Flutter multi-platform work starts, per the approved sequence.

The unchecked W2/W4 plan acceptance items remain unchecked until these external gates have evidence.
