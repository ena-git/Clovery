# Clovery Backend Deployment Gate

This procedure is mandatory for staging and production. The API never migrates the database automatically.

The executable staging profile is `infra/staging/compose.yaml`. It contains only the API and one-shot migration job; it does not declare PostgreSQL, object storage, or development volumes. Keep the environment file, database dumps, restore evidence, and smoke evidence outside the Git repository.

## 0. Prepare staging inputs

1. Publish `services/api/Dockerfile` to the registry and record the immutable image digest and full release commit SHA.
2. Provision managed PostgreSQL, a separate `_restore` database, a private S3-compatible bucket, an HTTPS API hostname, and secret-manager entries.
3. Create protected operational directories outside the repository:

   ```bash
   install -d -m 700 /opt/clovery/staging/backups /opt/clovery/staging/evidence
   cp infra/staging/.env.example /opt/clovery/staging/.env
   chmod 600 /opt/clovery/staging/.env
   ```

4. Replace every placeholder in `/opt/clovery/staging/.env`. Leave all Apple IAP fields empty together until the complete sandbox configuration is available; partial billing configuration is rejected.
5. Run the local contract gate and migration-phase preflight:

   ```bash
   make verify-staging
   ./scripts/staging-preflight.sh /opt/clovery/staging/.env migration
   ```

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

For staging, create a timestamped, checksummed custom-format dump. The destination must already exist outside Git:

```bash
BACKUP_DIRECTORY=$(./scripts/staging-backup.sh \
  /opt/clovery/staging/.env \
  /opt/clovery/staging/backups)
```

Prepare `/opt/clovery/staging/restore.env` with `RESTORE_DRILL_ENVIRONMENT=staging`, a TLS `RESTORE_DATABASE_URL` whose database name ends in `_restore` or `_restore_drill`, and `CLOVERY_ALLOW_RESTORE_DRILL=yes`. Build the migration binary from the same release image or source SHA, then prove the dump can be restored:

```bash
RESTORE_EVIDENCE=$(CLOVERY_MIGRATE_BIN=/opt/clovery/bin/clovery-migrate \
  ./scripts/staging-restore-drill.sh \
  /opt/clovery/staging/.env \
  "$BACKUP_DIRECTORY" \
  /opt/clovery/staging/restore.env)
```

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
   docker compose --env-file /opt/clovery/staging/.env \
     -f infra/staging/compose.yaml --profile migration run --rm migrate
   ```

3. Run `./scripts/staging-preflight.sh /opt/clovery/staging/.env runtime`, then deploy the API only after the migration job exits successfully:

   ```bash
   docker compose --env-file /opt/clovery/staging/.env \
     -f infra/staging/compose.yaml up -d api
   ```

4. Verify `/v1/health` and bearer-protected `/internal/metrics`, retaining only hashed payload evidence:

   ```bash
   SMOKE_EVIDENCE=$(./scripts/staging-smoke.sh \
     /opt/clovery/staging/.env \
     https://api.staging.clovery.cn \
     /opt/clovery/staging/evidence)
   ```

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

Retain the backup ID, restore evidence, migration output, release SHA, immutable image digest, smoke-test output, notification test result, and approver names. Do not retain passwords, tokens, signed payloads, journal text, image URLs, or private object contents in release logs.

Bind backup, restore, and smoke evidence to the exact release SHA:

```bash
./scripts/staging-evidence-manifest.sh \
  /opt/clovery/staging/.env \
  "$BACKUP_DIRECTORY" \
  "$RESTORE_EVIDENCE" \
  "$SMOKE_EVIDENCE" \
  /opt/clovery/staging/evidence
```

Before provider and billing acceptance, set `MIGRATION_WRITES_ENABLED=true`, configure all Apple/Google/Huawei OIDC fields and the complete Apple sandbox IAP group, then run:

```bash
./scripts/staging-preflight.sh /opt/clovery/staging/.env acceptance
```

Passing preflight proves configuration completeness only. W2/W4 remain open until real staging identity, Vault, migration, object-store, notification, and entitlement flows produce evidence.
