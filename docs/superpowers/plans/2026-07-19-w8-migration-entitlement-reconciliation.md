# W8 Legacy Migration and Entitlement Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make legacy diary/photo migration non-destructive and idempotent, preserve conflicting content, bind App Store purchases to the authenticated Clovery account, and drive the corresponding server bootstrap stages to completion.

**Architecture:** Extend migration staging rows with deterministic resolution metadata. Verification resolves each source entry against existing vault content before publishing any change: exact and canonical-content duplicates become aliases, ID collisions with different content receive stable conflict IDs, and uncertain cases remain separate. Existing Apple transaction verification remains the authority for purchases; thin application-flow wrappers update bootstrap state only after migration verification or a complete StoreKit inventory restore succeeds.

**Tech Stack:** Go 1.24, PostgreSQL 16, pgx, existing Vault migration/sync and Apple App Store Server API services, OpenAPI 3.1, Go unit and PostgreSQL integration tests.

---

## Scope, Dependency, and Acceptance Boundary

This workflow starts after W7 has added `account_bootstrap_jobs` and the `bootstrapjob` service. It does not depend on iOS views and can be accepted through API and database tests.

W8 is accepted when:

1. Repeating the same migration changes neither journal counts nor sync history.
2. Same source ID plus same canonical content resolves to one entry.
3. Different source IDs plus same canonical active content resolve to one entry.
4. Same source ID plus different content preserves both using a deterministic conflict ID.
5. Deleted tombstones with different source IDs and any uncertain match are preserved separately.
6. Verification failure leaves `journal_entries` and `sync_changes` unchanged.
7. Photo manifests and completed object hashes are verified; no local or uploaded asset is deleted by reconciliation.
8. A legacy Apple purchase can be claimed once by a Clovery account, replayed by that account, and never moved automatically to another account.
9. A successful full StoreKit inventory restore, including an empty inventory, marks the entitlement stage complete.
10. Migration and entitlement failures produce stable bootstrap states and support-safe error codes.

## Resolution Rules

Resolution is deterministic and ordered:

| Condition | Resolution | Vault change |
| --- | --- | --- |
| Target has same internal ID, payload, and deleted state | `exact_duplicate` | Reuse target ID; publish nothing. |
| Active target has another ID but the same canonical payload SHA and JSON | `content_duplicate` | Reuse the oldest matching target ID; publish nothing. |
| Target has same internal ID but different payload or deleted state | `id_conflict_copy` | Insert under deterministic conflict ID; publish one sync change. |
| No certain match | `insert` | Insert original normalized ID; publish one sync change. |
| Different source IDs are tombstones with empty payload | `insert` | Preserve separately; never collapse uncertain deletions. |

Canonical content matching uses two separate hashes:

```text
sha256       = exact canonical payload, including its legacy id; integrity only
dedup_sha256 = canonical payload after removing identity-only keys
               id and clovery_legacy_source_id; duplicate candidate lookup
```

After a `dedup_sha256` match, Go compares the normalized JSON bytes with identity-only keys removed. Hash equality alone is never sufficient. Dates, text, tags, ordering, photos, language, and every other user field remain part of dedup content. For active content duplicates inside one migration, sort by `source_entry_id` and use the first resolved entry as canonical.

Conflict IDs are stable across retries and new migration bundles containing the same source content:

```go
func conflictEntryID(vaultID, sourceEntryID, contentSHA256 string) uuid.UUID {
    return uuid.NewSHA1(
        migrationConflictNamespace,
        []byte(vaultID+"\x00"+sourceEntryID+"\x00"+contentSHA256),
    )
}
```

If that deterministic ID already exists with different content, append `\x00<counter>` and increment from `1` under the verification transaction until a free ID is found. Record the chosen ID in staging so subsequent verification returns the same result.

## Task 1: Add Migration Resolution Persistence

**Files:**
- Create: `v2/services/api/migrations/000017_migration_resolution.up.sql`
- Create: `v2/services/api/migrations/000017_migration_resolution.down.sql`
- Create: `v2/services/api/internal/database/migration_resolution_migration_test.go`
- Modify: `v2/contracts/openapi/openapi.yaml`

- [ ] **Step 1: Write the migration contract test**

Require these schema fragments:

```go
for _, fragment := range []string{
    "ADD COLUMN resolved_entry_id UUID",
    "ADD COLUMN resolution TEXT NOT NULL DEFAULT 'pending'",
    "migration_entries_resolution_check",
    "ADD COLUMN dedup_sha256 TEXT",
    "ADD COLUMN content_sha256 TEXT",
    "journal_entries_vault_dedup_sha_idx",
} {
    if !strings.Contains(up, fragment) {
        t.Fatalf("migration missing %q", fragment)
    }
}
```

Also assert the down migration drops the partial index and added columns.

- [ ] **Step 2: Run the focused test and observe the missing migration**

```bash
cd /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/v2/services/api
GOCACHE=/private/tmp/clovery-go-build go test ./internal/database -run MigrationResolution
```

Expected: failure because migration `000017` does not exist.

- [ ] **Step 3: Add forward-compatible resolution columns**

Use:

```sql
ALTER TABLE migration_entries
    ADD COLUMN resolved_entry_id UUID,
    ADD COLUMN dedup_sha256 TEXT,
    ADD COLUMN resolution TEXT NOT NULL DEFAULT 'pending',
    ADD CONSTRAINT migration_entries_resolution_check CHECK (
        resolution IN ('pending', 'insert', 'exact_duplicate', 'content_duplicate', 'id_conflict_copy')
    ),
    ADD CONSTRAINT migration_entries_dedup_sha256_format CHECK (
        dedup_sha256 IS NULL OR dedup_sha256 ~ '^[a-f0-9]{64}$'
    ),
    ADD CONSTRAINT migration_entries_resolution_target_check CHECK (
        (resolution = 'pending' AND resolved_entry_id IS NULL)
        OR (resolution <> 'pending' AND resolved_entry_id IS NOT NULL)
    );

ALTER TABLE journal_entries
    ADD COLUMN content_sha256 TEXT,
    ADD COLUMN dedup_sha256 TEXT,
    ADD CONSTRAINT journal_entries_content_sha256_format CHECK (
        content_sha256 IS NULL OR content_sha256 ~ '^[a-f0-9]{64}$'
    ),
    ADD CONSTRAINT journal_entries_dedup_sha256_format CHECK (
        dedup_sha256 IS NULL OR dedup_sha256 ~ '^[a-f0-9]{64}$'
    );

CREATE INDEX journal_entries_vault_dedup_sha_idx
    ON journal_entries (vault_id, dedup_sha256, updated_at, id)
    WHERE deleted_at IS NULL AND dedup_sha256 IS NOT NULL;
```

Existing journal rows remain nullable. Resolution loads active target rows with missing hashes, computes exact and identity-stripped canonical JSON in Go, and backfills both hashes inside the verification transaction before candidate lookup. Do not add `pgcrypto` or calculate a digest from PostgreSQL text rendering.

- [ ] **Step 4: Expose resolution counts in migration reports**

Extend the OpenAPI report with:

```yaml
inserted_entries:
  type: integer
duplicate_entries:
  type: integer
conflict_copies:
  type: integer
```

Keep existing expected/imported fields for compatibility. Define `imported_entries` as uploaded staging entries and `inserted_entries` as rows actually added to the vault.

- [ ] **Step 5: Run migration and contract tests**

```bash
GOCACHE=/private/tmp/clovery-go-build go test ./internal/database ./internal/contract
```

Expected: both packages pass.

- [ ] **Step 6: Commit the resolution schema**

```bash
git add v2/services/api/migrations/000017_migration_resolution.* \
  v2/services/api/internal/database/migration_resolution_migration_test.go \
  v2/contracts/openapi/openapi.yaml
git commit -m "feat(migration): add deterministic resolution metadata"
```

## Task 2: Build a Pure Entry Resolution Engine

**Files:**
- Create: `v2/services/api/internal/migration/resolution.go`
- Create: `v2/services/api/internal/migration/resolution_test.go`
- Modify: `v2/services/api/internal/migration/entry_identity.go`
- Modify: `v2/services/api/internal/migration/manifest.go`

- [ ] **Step 1: Write table-driven resolution tests**

Model staged and existing entries without SQL:

```go
type ResolutionCandidate struct {
    SourceEntryID string
    EntryID       string
    Payload       json.RawMessage
    DedupPayload  json.RawMessage
    ContentSHA256 string
    DedupSHA256   string
    DeletedAt     *time.Time
}

type ExistingEntry struct {
    EntryID       string
    Payload       json.RawMessage
    DedupPayload  json.RawMessage
    ContentSHA256 string
    DedupSHA256   string
    DeletedAt     *time.Time
    UpdatedAt     time.Time
}
```

Cover at least:

```text
same ID + same active JSON with different key ordering -> exact_duplicate
same ID + different JSON -> id_conflict_copy
different ID + same active JSON -> content_duplicate
same dedup SHA + different normalized JSON -> insert
different tombstone IDs -> insert twice
same tombstone ID + same deleted state -> exact_duplicate
same source/content across migration IDs -> same conflict UUID
two staged active duplicates -> first source ID is canonical
pre-existing deterministic conflict ID with other content -> salted stable fallback
```

- [ ] **Step 2: Run focused tests and observe failure**

```bash
GOCACHE=/private/tmp/clovery-go-build go test ./internal/migration -run Resolution
```

Expected: missing resolution engine.

- [ ] **Step 3: Implement exact and identity-stripped canonical forms**

Reuse `canonicalJSON` for integrity. Add `canonicalDedupJSON` that requires an object payload, copies it, removes only `id` and `clovery_legacy_source_id`, then serializes with stable key ordering. Equality requires:

```go
func sameCanonicalContent(left, right ResolutionCandidate) bool {
    return left.DeletedAt == nil && right.DeletedAt == nil &&
        left.DedupSHA256 == right.DedupSHA256 &&
        bytes.Equal(left.DedupPayload, right.DedupPayload)
}
```

Use `ContentSHA256` plus exact canonical payload for same-source equality. Use explicit deleted-state comparison for exact source matches. Do not remove dates, text, tags, photo lists, or user metadata from dedup JSON; do not use timestamps outside the payload to merge active entries; and do not collapse tombstones across different source IDs.

- [ ] **Step 4: Implement stable conflict IDs**

Create a dedicated namespace UUID constant. The function takes vault ID, original source ID, digest, and optional collision counter. It must not use migration ID, current time, or randomness.

- [ ] **Step 5: Run focused and race tests**

```bash
GOCACHE=/private/tmp/clovery-go-build go test -race ./internal/migration -run 'Resolution|EntryIdentity|Manifest'
```

Expected: all pure resolution tests pass.

- [ ] **Step 6: Commit the resolution engine**

```bash
git add v2/services/api/internal/migration/resolution.go \
  v2/services/api/internal/migration/resolution_test.go \
  v2/services/api/internal/migration/entry_identity.go \
  v2/services/api/internal/migration/manifest.go
git commit -m "feat(migration): resolve duplicate legacy entries"
```

## Task 3: Replace Collision Failure with Atomic Non-Destructive Import

**Files:**
- Modify: `v2/services/api/internal/migration/verify_repository.go`
- Modify: `v2/services/api/internal/migration/report_repository.go`
- Modify: `v2/services/api/internal/migration/types.go`
- Modify: `v2/services/api/internal/migration/repository_upload.go`
- Modify: `v2/services/api/internal/migration/service.go`
- Modify: `v2/services/api/internal/migration/postgres_integration_test.go`
- Create: `v2/services/api/internal/migration/resolution_postgres_integration_test.go`
- Modify: `v2/services/api/internal/http/migration_contract.go`
- Modify: `v2/services/api/internal/http/migration_handler.go`
- Modify: `v2/services/api/internal/http/migration_handler_test.go`
- Modify: `v2/contracts/openapi/openapi.yaml`

- [ ] **Step 1: Write PostgreSQL acceptance cases before changing verification**

Seed one vault per case and assert both `journal_entries` and `sync_changes` counts:

```text
empty Vault import -> one inserted row and one sync change
same migration verified twice -> one inserted row and one sync change
same ID/same content already in Vault -> zero inserted rows, zero new sync changes
different ID/same active content -> zero inserted rows, alias points to existing ID
same ID/different content -> one conflict copy, original unchanged
two staged rows/same active content -> one insert, one alias, one sync change
manifest/count/hash failure -> no journal or sync rows changed
concurrent verify -> one committed resolution set
```

For each accepted migration, assert every staging row has non-`pending` resolution and non-null `resolved_entry_id`.

- [ ] **Step 2: Run the focused database tests and verify current collision behavior fails**

```bash
DATABASE_URL='postgres://clovery:clovery@localhost:5432/clovery_test?sslmode=disable' \
  GOCACHE=/private/tmp/clovery-go-build \
  go test ./internal/migration -run 'Postgres.*Resolution|Postgres.*Duplicate'
```

Expected: ID-conflict cases return `ErrEntryCollision` or insert counts differ.

- [ ] **Step 3: Resolve all staging rows while holding the migration lock**

Refactor `Verify` into small transaction-scoped helpers:

```text
lockAndLoadMigration
validateMigrationIntegrity
loadResolutionCandidates
loadExistingResolutionEntries
resolveMigrationEntries
persistMigrationResolutions
insertResolvedEntries
publishResolvedChanges
completeMigration
```

Do not place the resolver, SQL loading, insertion, sync publishing, report updates, and audit logic in one function.

`AddEntry` computes and stores both hashes after canonical validation. Deleted entries keep the exact empty-object `sha256` and leave `dedup_sha256` null because cross-source tombstone deduplication is prohibited.

- [ ] **Step 4: Insert only `insert` and `id_conflict_copy` rows**

Use `resolved_entry_id`, set `content_sha256`, and preserve `deleted_at`:

```sql
INSERT INTO journal_entries (
    id, vault_id, revision, payload, deleted_at, updated_at,
    imported_by_migration_id, content_sha256, dedup_sha256
)
SELECT resolved_entry_id, $2, 1, payload, deleted_at, $3, $1, sha256, dedup_sha256
FROM migration_entries
WHERE migration_id = $1
  AND resolution IN ('insert', 'id_conflict_copy');
```

Treat any unexpected conflict at this point as transaction failure. Never `ON CONFLICT DO NOTHING` after resolution because it can hide a race.

`journal_entries.id` and `sync_changes.entity_id` are authoritative. A conflict copy may retain the original legacy `payload.id` so exact source content remains comparable; W9 must overwrite `payload.id` with `entity_id` only while materializing the local WebView model.

- [ ] **Step 5: Publish sync changes only for inserted rows**

Use `resolved_entry_id` as `entity_id`. Duplicate aliases must not create sync changes. Repeated `Verify` returns the stored report without publishing again.

- [ ] **Step 6: Preserve and verify assets**

Keep the existing manifest byte/hash and completed-asset checks. Add a test proving two photos with equal SHA but distinct filenames remain available until a later storage compaction workflow; W8 must not delete or re-point uploaded objects because legacy payload references may still use filenames.

- [ ] **Step 7: Expose verified migration asset mappings for another device**

Register this protected route:

```text
GET /v1/vault/migrations/{migrationId}/assets
```

Return only assets owned by the authenticated vault and only after the migration is verified:

```json
{
  "assets": [
    {
      "source_filename": "photo-0001.jpg",
      "asset_id": "44444444-4444-4444-8444-444444444444",
      "byte_size": 1024,
      "sha256": "64-lowercase-hex"
    }
  ]
}
```

The response supplies the stable filename-to-asset mapping needed by W9. The client obtains download tickets through the existing protected `/v1/vault/assets/{assetId}/download` route. The mapping endpoint never returns object keys, presigned URLs, another vault's assets, or unverified uploads. Add service/repository/handler/OpenAPI tests for ownership, not-found, uploading-state rejection, and deterministic filename ordering.

- [ ] **Step 8: Return detailed report counts**

Calculate:

```sql
COUNT(*) FILTER (WHERE resolution IN ('insert', 'id_conflict_copy')) AS inserted_entries,
COUNT(*) FILTER (WHERE resolution IN ('exact_duplicate', 'content_duplicate')) AS duplicate_entries,
COUNT(*) FILTER (WHERE resolution = 'id_conflict_copy') AS conflict_copies
```

No report field may include diary text, photo filenames, or complete hashes.

- [ ] **Step 9: Remove collision as a normal user-facing failure**

Delete `ErrEntryCollision` from normal verification and remove the HTTP `entry_collision` mapping. Retain a new internal `ErrResolutionRace` mapped to generic `migration_verification_failed`; it indicates a server race, not user data loss.

- [ ] **Step 10: Run migration tests**

```bash
GOCACHE=/private/tmp/clovery-go-build go test -race ./internal/migration ./internal/http -run 'Migration|Resolution'
```

Expected: all unit tests pass; database tests pass when `DATABASE_URL` is set.

- [ ] **Step 11: Commit non-destructive migration**

```bash
git add v2/services/api/internal/migration v2/services/api/internal/http \
  v2/contracts/openapi/openapi.yaml
git commit -m "feat(migration): preserve and deduplicate legacy data"
```

## Task 4: Connect Migration Results to Bootstrap State

**Files:**
- Create: `v2/services/api/internal/application/migrationflow/service.go`
- Create: `v2/services/api/internal/application/migrationflow/service_test.go`
- Modify: `v2/services/api/cmd/api/migration_bootstrap.go`
- Modify: `v2/services/api/cmd/api/bootstrap.go`
- Modify: `v2/services/api/cmd/api/bootstrap_test.go`

- [ ] **Step 1: Write orchestration tests with spies**

Require:

```text
Create attaches migration ID to the authenticated account job
successful Verify marks migration complete
integrity or manifest failure marks migration needs_attention
transport/database unavailable leaves migration pending and records retryable error
repeated successful Verify remains complete
another account's migration cannot update the job
```

- [ ] **Step 2: Run the focused tests and observe missing flow**

```bash
GOCACHE=/private/tmp/clovery-go-build go test ./internal/application/migrationflow
```

Expected: package does not exist.

- [ ] **Step 3: Implement a thin application wrapper**

The wrapper implements the existing `httpapi.MigrationHTTPApplication` contract and delegates content logic to `migration.Service`. It updates `bootstrapjob.Service` only after domain calls return. It never contains SQL.

Map stable state:

```go
switch {
case err == nil:
    tracker.MarkMigration(ctx, accountID, migrationID, bootstrapjob.StageComplete, nil)
case errors.Is(err, migration.ErrIntegrityMismatch),
     errors.Is(err, migration.ErrVerificationFailed):
    tracker.MarkMigration(ctx, accountID, migrationID, bootstrapjob.StageNeedsAttention, ptr("migration_integrity_failed"))
default:
    tracker.RecordRetryableError(ctx, accountID, "migration_temporarily_unavailable")
}
```

- [ ] **Step 4: Wire the wrapper in `cmd/api`**

Construct migration domain service, bootstrap job service, then migration flow. Do not create a second bootstrap repository for each request.

- [ ] **Step 5: Run affected tests**

```bash
GOCACHE=/private/tmp/clovery-go-build go test ./internal/application/migrationflow ./cmd/api ./internal/http
```

Expected: all packages pass.

- [ ] **Step 6: Commit bootstrap migration tracking**

```bash
git add v2/services/api/internal/application/migrationflow v2/services/api/cmd/api
git commit -m "feat(bootstrap): track legacy migration completion"
```

## Task 5: Make Apple Entitlement Reconciliation Account-Complete

**Files:**
- Modify: `v2/services/api/internal/billing/service.go`
- Modify: `v2/services/api/internal/billing/service_test.go`
- Modify: `v2/services/api/internal/billing/legacy_claim_service_test.go`
- Create: `v2/services/api/internal/application/billingflow/service.go`
- Create: `v2/services/api/internal/application/billingflow/service_test.go`
- Modify: `v2/services/api/cmd/api/billing_bootstrap.go`
- Modify: `v2/services/api/cmd/api/bootstrap.go`
- Modify: `v2/services/api/internal/http/billing_handler_test.go`
- Modify: `v2/contracts/openapi/openapi.yaml`

- [ ] **Step 1: Preserve existing purchase-chain security tests**

Add explicit regression names for:

```text
first unassigned legacy transaction is reserved then assigned to account
same account replays the same legacy proof idempotently
another account cannot claim the reserved original transaction chain
Sign in with Apple subject is never passed to billing claim
failed Apple assignment does not create an active entitlement
```

Do not weaken `appAccountToken == clovery_account_id` validation.

- [ ] **Step 2: Add an empty inventory restore test**

Change `billing.Service.Restore` so a valid account and environment with `transaction_ids: []` returns the account's current server entitlements. This is the explicit client assertion that StoreKit enumeration completed and found no current transactions; it never grants an entitlement.

The test must prove malformed account IDs, invalid environments, and more than 100 IDs remain rejected.

- [ ] **Step 3: Run billing tests and observe the empty inventory failure**

```bash
GOCACHE=/private/tmp/clovery-go-build go test ./internal/billing -run 'Legacy|Restore'
```

Expected: empty restore currently returns `ErrInvalidRequest`.

- [ ] **Step 4: Implement the minimal restore change**

Validate account UUID and environment before the list loop. Accept zero through 100 IDs. Deduplicate IDs before verification. If any transaction verification fails, return the error and do not declare reconciliation complete.

- [ ] **Step 5: Write billing-flow bootstrap tests**

Require:

```text
successful restore with active purchases marks entitlement complete
successful empty restore marks entitlement complete with empty response
legacy claim success keeps stage running until final restore inventory call
transaction already owned by another account marks needs_attention
Apple verification unavailable keeps pending and records retryable error
list alone does not mark reconciliation complete
```

- [ ] **Step 6: Implement `application/billingflow`**

Delegate all billing verification to `billing.Service`. Only `Restore` finalizes the bootstrap entitlement stage. Map `ErrTransactionClaimed` and `ErrAccountMismatch` to `needs_attention`; map `ErrVerificationUnavailable` to pending. Do not accept account IDs from the request body.

- [ ] **Step 7: Update OpenAPI wording**

Document that an empty `transaction_ids` array is valid and means “StoreKit enumeration completed with no current verified transactions.” It does not remove existing server entitlements; server notifications and revocation state remain authoritative.

- [ ] **Step 8: Run billing, flow, handler, and contract tests**

```bash
GOCACHE=/private/tmp/clovery-go-build go test -race \
  ./internal/billing \
  ./internal/application/billingflow \
  ./internal/http \
  ./internal/contract \
  ./cmd/api
```

Expected: all packages pass.

- [ ] **Step 9: Commit entitlement reconciliation**

```bash
git add v2/services/api/internal/billing \
  v2/services/api/internal/application/billingflow \
  v2/services/api/internal/http \
  v2/services/api/cmd/api \
  v2/contracts/openapi/openapi.yaml
git commit -m "feat(billing): reconcile Apple rights to accounts"
```

## Task 6: Confirm Vault Pull Before Bootstrap Completion

**Files:**
- Modify: `v2/services/api/internal/bootstrapjob/types.go`
- Modify: `v2/services/api/internal/bootstrapjob/repository.go`
- Modify: `v2/services/api/internal/bootstrapjob/service.go`
- Modify: `v2/services/api/internal/bootstrapjob/service_test.go`
- Modify: `v2/services/api/internal/http/bootstrap_contract.go`
- Modify: `v2/services/api/internal/http/bootstrap_handler.go`
- Modify: `v2/services/api/internal/http/bootstrap_handler_test.go`
- Modify: `v2/services/api/internal/sync/repository.go`
- Modify: `v2/contracts/openapi/openapi.yaml`

- [ ] **Step 1: Add failing vault checkpoint tests**

Extend `POST /v1/account/bootstrap/resume` with optional:

```json
{
  "source_kind": "legacy_local",
  "vault_checkpoint": {
    "cursor": 42,
    "has_more": false
  }
}
```

Require:

```text
cursor lower than current server maximum keeps vault pending
has_more=true keeps vault pending
cursor equal to or above current server maximum and has_more=false marks vault complete
checkpoint is checked only against authenticated vault
all four stages complete changes overall status to complete
later sync changes do not reopen the one-time bootstrap job
```

- [ ] **Step 2: Expose a maximum cursor query**

Add a small repository method:

```go
LatestCursor(ctx context.Context, vaultID string) (int64, error)
```

Its SQL is:

```sql
SELECT COALESCE(MAX(cursor), 0) FROM sync_changes WHERE vault_id = $1;
```

- [ ] **Step 3: Validate checkpoint in bootstrap service**

Do not trust `has_more=false` by itself. Mark vault complete only after the submitted cursor covers the server cursor observed in the same request. The checkpoint does not permit migration or entitlement stages to be client-completed.

- [ ] **Step 4: Run bootstrap and sync tests**

```bash
GOCACHE=/private/tmp/clovery-go-build go test -race ./internal/bootstrapjob ./internal/sync ./internal/http -run 'Bootstrap|Cursor'
```

Expected: all tests pass.

- [ ] **Step 5: Commit vault confirmation**

```bash
git add v2/services/api/internal/bootstrapjob \
  v2/services/api/internal/sync \
  v2/services/api/internal/http \
  v2/contracts/openapi/openapi.yaml
git commit -m "feat(bootstrap): verify initial vault pull"
```

## Task 7: Verify W8 as an Independent Deliverable

**Files:**
- Create: `docs/superpowers/verification/2026-07-19-w8-migration-entitlement.md`

- [ ] **Step 1: Run migrations and PostgreSQL integration suites**

```bash
cd /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/v2
docker compose up -d postgres
cd services/api
DATABASE_URL='postgres://clovery:clovery@localhost:5432/clovery_test?sslmode=disable' \
  GOCACHE=/private/tmp/clovery-go-build \
  go test ./internal/migration ./internal/billing ./internal/bootstrapjob
```

Expected: all enabled tests pass.

- [ ] **Step 2: Run the full backend gate**

```bash
GOCACHE=/private/tmp/clovery-go-build go test ./...
GOCACHE=/private/tmp/clovery-go-build go build ./cmd/api
gofmt -w internal/migration internal/billing internal/bootstrapjob \
  internal/application/migrationflow internal/application/billingflow internal/http cmd/api
git diff --check
```

Expected: tests/build exit `0`; no formatting diff or whitespace error.

- [ ] **Step 3: Record acceptance evidence**

The verification document must include:

- tested commit SHA and database migration versions;
- before/after row counts for all five resolution cases;
- confirmation of zero Vault writes after an integrity failure;
- duplicate and conflict-copy report examples without diary content;
- legacy purchase first claim, same-account replay, and cross-account rejection;
- empty StoreKit inventory result;
- final bootstrap stage transitions;
- full commands and exit codes.

- [ ] **Step 4: Commit and push W8**

```bash
git add docs/superpowers/verification/2026-07-19-w8-migration-entitlement.md
git commit -m "test(reconciliation): verify legacy inheritance"
git push origin codex/swift-auth-foundation
```

Expected: remote branch contains W8 and the working tree is clean.

## W8 Non-Goals

- Do not delete local backup files after migration.
- Do not delete duplicate uploaded photo objects during account bootstrap.
- Do not auto-merge two existing Clovery accounts.
- Do not infer purchase ownership from Apple Sign in, email, device, or local paid flags.
- Do not let a client directly mark migration or entitlement stages complete.
- Do not add Flutter, Android, or HarmonyOS UI in this workflow.
