# Migration Rollback Runbook

## Trigger and ownership

The incident commander is the backend on-call engineer. The data owner approves any restore, and customer support owns user communication. Start this runbook when any of the following occurs:

- migration validation mismatches exceed 1% in 15 minutes;
- a verified migration changes an existing journal entry;
- imported entry, asset, or byte totals differ from the source manifest;
- cross-account access is suspected;
- database or object-store writes become partially unavailable.

## Immediate containment

1. Set `MIGRATION_WRITES_ENABLED=false` in the API deployment and roll out the configuration. Keep report reads available.
2. Confirm new migration create, entry, asset, and verify requests return `503 migration_disabled`.
3. Do not delete V1 exports, legacy CloudKit data, local journals, pending objects, or failed migration rows.
4. Record the incident start time, release SHA, database migration version, affected migration IDs, and aggregate counts. Never copy journal text, credentials, email addresses, tokens, or image URLs into the incident record.
5. If account isolation may be broken, stop the entire API deployment and escalate to the security owner.

## Evidence and backup

1. Create a production database snapshot using the managed PostgreSQL backup facility. For a self-managed emergency copy, run:

   ```bash
   pg_dump --format=custom --no-owner --file=clovery-incident.dump "$DATABASE_URL"
   ```

2. Record the object-store versioning state and retain all versions for the incident window.
3. Export only identifiers and integrity metadata needed for reconciliation: migration ID, vault ID, status, counts, byte totals, hashes, timestamps, and audit event IDs.
4. Store backups and evidence in the restricted incident location; do not attach them to chat or tickets.

## Recovery

1. Restore the backup into a new database instance, never over the production database:

   ```bash
   createdb clovery_restore_validation
   pg_restore --clean --if-exists --no-owner --dbname=clovery_restore_validation clovery-incident.dump
   ```

2. Reconcile the affected migration against its retained V1 Bundle: format version, raw `entries.json`/`deleted_ids.json` hashes, exact source IDs, per-entry canonical bytes and SHA-256, deletion tombstones, asset bytes, and asset SHA-256 values.
3. If the defect is limited to unverified rows, leave target journals untouched and mark the affected migrations failed through an audited repair job.
4. If verified imports are corrupted, prepare a migration-ID-scoped compensating transaction in staging. It may remove only rows whose `imported_by_migration_id` matches the affected migration; it must not delete pre-existing entries or objects.
5. Validate the repair on the restored database, then staging, before the data owner approves production execution.
6. Re-enable migration writes only after one real retained Bundle passes twice idempotently and all aggregate counters match.

## User communication template

> We temporarily paused Clovery data migration after detecting an integrity inconsistency. Your existing V1 data and export files remain unchanged. Please keep the original app data and migration Bundle. We will notify you before retrying; no action is required now.

## Audit and closure

- Attach approvals, backup identifiers, deployment SHAs, SQL repair hashes, aggregate before/after counts, and validation results.
- Confirm `audit_events` contains the migration verification and any repair event.
- Review alerts, add a regression test, and document the exact root cause.
- Customer support confirms all affected users received the resolution notice before closure.
