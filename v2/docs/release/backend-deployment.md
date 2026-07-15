# Clovery Backend Deployment Gate

This procedure is mandatory for staging and production. The API never migrates the database automatically.

## 1. Freeze identifiers and secrets

- Keep the production bundle ID, Clovery API hostname, PostgreSQL cluster, S3 bucket, and Apple product IDs unchanged across upgrades.
- Load database credentials, JWT signing key, passkey encryption key, provider secrets, Apple IAP key, and metrics token from the deployment secret manager.
- Production must use TLS PostgreSQL/S3 endpoints, `DEPLOYMENT_ENVIRONMENT=production`, the released numeric `APPLE_IAP_APP_APPLE_ID`, and `APPLE_IAP_ALLOW_SANDBOX=false`.

## 2. Back up before migration

1. Record the release SHA and current migration version.
2. Create a managed PostgreSQL snapshot. For a self-managed copy:

   ```bash
   pg_dump --format=custom --no-owner --file=clovery-before-release.dump "$DATABASE_URL"
   ```

3. Confirm object-store versioning and retention are enabled.
4. Restore the backup into an isolated database and run integrity checks. A backup that has not been restored successfully is not an accepted release backup.
5. Never delete or recreate the production database volume to repair a local development environment.

## 3. Validate migrations in isolation

Run against the restored database first:

```bash
cd v2/services/api
DATABASE_URL="$RESTORE_DATABASE_URL" MIGRATIONS_PATH=./migrations go run ./cmd/migrate up
DATABASE_URL="$RESTORE_DATABASE_URL" go test -count=1 ./internal/database ./internal/account ./internal/asset ./internal/sync ./internal/migration ./internal/billing ./internal/http ./internal/contract
```

Confirm existing account, Vault, journal, asset, purchase-chain, transaction, entitlement, and notification row counts remain expected. The production migration command accepts only `up`; restore the snapshot or deploy a reviewed forward repair instead of applying destructive down migrations.

Run the object-store overwrite gate against a disposable integration bucket:

```bash
MINIO_INTEGRATION_ENDPOINT="$S3_ENDPOINT" \
MINIO_INTEGRATION_ACCESS_KEY="$S3_ACCESS_KEY" \
MINIO_INTEGRATION_SECRET_KEY="$S3_SECRET_KEY" \
go test -count=1 -run TestMinIOPresignedUploadCannotOverwriteObject -v ./internal/asset
```

The integration identity must be allowed to create and remove only temporary `clovery-test-*` buckets. The test must prove the first conditional PUT succeeds, the replacement returns `412`, and the original bytes remain unchanged.

## 4. Deploy in order

1. Set `MIGRATION_WRITES_ENABLED=false` during the database change window.
2. Run the migration job once:

   ```bash
   DATABASE_URL="$DATABASE_URL" MIGRATIONS_PATH=./migrations go run ./cmd/migrate up
   ```

3. Deploy the API only after the migration job exits successfully.
4. Verify `/v1/health` and bearer-protected `/internal/metrics`.
5. Re-enable migration writes only after API smoke tests and retained-bundle validation succeed.

Before enabling writes, regenerate migration bundles with the current iOS exporter so `manifest.json` contains `entries_sha256`, `deleted_ids_sha256`, per-entry digests, and the exact deleted-ID list. Older weak manifests are rejected; original V1 data and previous archives remain untouched. Confirm legacy V1 IDs such as `new-<timestamp>` import idempotently and map to the same Vault-scoped UUID on retry.

## 5. Billing release gate

- Configure App Store Server Notifications V2 to call `POST /v1/billing/apple/notifications`.
- Send an Apple test notification in staging.
- Verify authenticated transaction validation, restore, expiry, refund, and refund reversal.
- Verify V1 legacy purchase claiming with a StoreKit-signed transaction that has no account token.
- Replay a short staging notification-history interval twice and confirm the second pass is idempotent.
- Confirm the same Clovery root account receives the entitlement after a new-device login.
- Never grant production entitlement from a client flag, email, device ID, or sandbox transaction.

## 6. Release evidence

Retain the backup ID, restore evidence, migration output, release SHA, environment checksum, smoke-test output, notification test result, and approver names. Do not retain passwords, tokens, signed payloads, journal text, image URLs, or private object contents in release logs.
