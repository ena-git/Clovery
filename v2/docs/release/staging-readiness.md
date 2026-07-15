# Clovery Staging Readiness

This checklist separates repository-complete work from cloud and provider acceptance. It does not mark W2 or W4 complete by itself.

## Repository ready

- [x] API image contains separate `clovery-api` and `clovery-migrate` binaries.
- [x] Staging Compose is isolated from development PostgreSQL and MinIO volumes.
- [x] Preflight rejects production, plaintext endpoints, mutable image tags, short release SHAs, partial provider configuration, placeholder secrets, and unsafe migration-write state.
- [x] Backup rejects a dirty migration state and captures a custom-format PostgreSQL dump, checksum, release SHA, and clean migration version without recording credentials.
- [x] Restore drill verifies the checksum, rejects the source database, requires a guarded `_restore` target, applies forward migrations, and records integrity counts.
- [x] Smoke test verifies health plus protected metrics and stores the release SHA, immutable image digest, and payload hashes instead of URLs, tokens, or private data.
- [x] Evidence manifest binds backup, restore, and smoke records to one release SHA and image digest.
- [x] PostgreSQL integration tests prove paginated Vault-scoped change pulls, persisted conflicts, tombstones, and rejection of post-delete resurrection.
- [x] `make verify-staging` runs all staging contracts and is included by `make verify-infra` in CI.

## Infrastructure required

- [ ] Immutable API image is pushed and reachable by digest.
- [ ] Managed staging PostgreSQL and isolated restore-drill database are provisioned with TLS.
- [ ] Private S3-compatible staging bucket has versioning, retention, least-privilege credentials, and a disposable integration bucket policy.
- [ ] `api.staging.clovery.cn` terminates HTTPS and forwards only to the loopback-bound API service.
- [ ] Secrets are stored outside Git and `/opt/clovery/staging/.env` is rendered with mode `0600`.
- [ ] Backup and evidence roots exist outside Git with mode `0700` and independent retention.

## Acceptance required

- [ ] Backup restore drill and forward migration complete against managed staging PostgreSQL.
- [ ] Conditional object-store write proves an existing object cannot be overwritten.
- [ ] Health and metrics smoke evidence matches the deployed release SHA and immutable image digest.
- [ ] Clovery ID/password, Passkey, Apple, Google, and Huawei enter the same `clovery_account_id` and `vault_id` only after explicit binding.
- [ ] Device revocation rejects refresh; cross-Vault access remains denied.
- [ ] V1 migration, pagination, retry, tombstone, and conflict scenarios pass against the real API.
- [ ] Apple sandbox purchase, restore, notification, expiry, refund, reversal, and legacy claim update the server entitlement ledger.
- [ ] Real-device testing remains deferred until the iOS experience is complete and before Flutter multi-platform implementation starts.
