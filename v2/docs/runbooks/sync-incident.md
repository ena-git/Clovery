# Sync Incident Runbook

## Trigger and ownership

The backend on-call engineer is incident commander; the mobile lead validates client behavior and the data owner approves repairs. Start this runbook for cursor gaps, duplicate operation effects, tombstone resurrection, sustained backlog, conflict spikes, missing assets, or cross-account sync responses.

## Immediate containment

1. If migration traffic contributes to the incident, set `MIGRATION_WRITES_ENABLED=false` and deploy the configuration.
2. If cross-account data exposure is possible, stop API traffic immediately and escalate to the security owner.
3. Tell users not to uninstall the app, clear local storage, delete V1 data, or discard migration Bundles.
4. Do not run bulk retry, cursor reset, tombstone deletion, or object cleanup jobs during containment.
5. Record release SHA, affected cursor range, operation IDs, entry IDs, device counts, and aggregate backlog/conflict values without payloads or asset URLs.

## Evidence and backup

1. Create a database snapshot before repair:

   ```bash
   pg_dump --format=custom --no-owner --file=clovery-sync-incident.dump "$DATABASE_URL"
   ```

2. Preserve object-store versions and incomplete uploads for the incident window.
3. Restore the database into an isolated validation instance:

   ```bash
   createdb clovery_sync_restore
   pg_restore --clean --if-exists --no-owner --dbname=clovery_sync_restore clovery-sync-incident.dump
   ```

4. Reconstruct the affected Vault stream from `sync_operations`, `sync_changes`, `journal_entries`, `journal_conflicts`, and tombstones. Compare operation IDs, revisions, and cursors only; journal contents stay restricted.

## Diagnosis and repair

1. Confirm every accepted operation ID has one receipt and no changed replay was accepted.
2. Confirm cursors are increasing and each pull page resumes strictly after the prior cursor.
3. Confirm stale `base_revision` writes generated conflicts rather than overwriting the server snapshot.
4. Confirm deleted entries retain tombstones and cannot be recreated by stale operations.
5. Confirm assets are complete only after server-side size and SHA-256 verification.
6. Build a Vault-scoped, idempotent repair job. Test it against the restored database and staging; never update all Vaults or delete source records.
7. After approval, run the repair with dry-run counts, execute once, then rerun to prove it is idempotent.

## Recovery validation

- Push the same operation twice and verify one effect.
- Pull at least two pages and verify cursor continuity.
- Reproduce concurrent editing and confirm an explicit conflict.
- Delete on one device and confirm no resurrection on another.
- Download a repaired asset and verify its SHA-256.
- Keep V1 and local device data until two-device acceptance succeeds.

## User communication template

> We detected a synchronization issue and paused related processing while protecting your existing local and V1 data. Please keep the app installed and avoid clearing local data. Your content remains on your devices; we will notify you when normal synchronization is restored.

## Audit and closure

- Attach backup identifiers, approvals, repair-job hash, dry-run and final aggregate counts, and two-device validation evidence.
- Confirm no journal text, image URL, password, token, email, or Clovery login ID entered logs or dashboards.
- Add regression tests for the root cause and retain tombstones/backups through the defined recovery window.
