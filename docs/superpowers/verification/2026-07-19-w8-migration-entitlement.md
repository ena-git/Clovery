# W8 Legacy Migration and Entitlement Reconciliation Verification

**Verified code commit:** `e82af8de4d7d61cea1bb6186e6ef4b1d64e9938d`  
**Verification date:** 2026-07-27  
**Database:** PostgreSQL 16.13  
**Applied migration range:** `000001` through `000017_migration_resolution`

## Acceptance Result

W8 is accepted as an independent backend deliverable. Legacy journal import is atomic, idempotent, and non-destructive; photo mappings remain available after verification; Apple purchase chains remain bound to one Clovery account; empty StoreKit inventory reconciliation is valid; and migration, entitlement, and initial Vault pull stages update the account bootstrap job.

Live App Store Server API credentials were not used in this local gate. Production and sandbox Apple-provider evidence remains an external release-closure requirement and must not be inferred from these deterministic verifier tests.

## Migration Resolution Evidence

The PostgreSQL acceptance suite recreated an isolated schema for every case and observed these row counts:

| Case | Journal before/after | Sync before/after | Report result |
| --- | --- | --- | --- |
| Empty Vault import | `0 → 1` | `0 → 1` | inserted `1`, duplicate `0`, conflict `0` |
| Same ID and same canonical content | `1 → 1` | `0 → 0` | inserted `0`, duplicate `1`, conflict `0` |
| Different ID and same active content | `1 → 1` | `0 → 0` | inserted `0`, duplicate `1`, conflict `0` |
| Same ID and different content | `1 → 2` | `0 → 1` | inserted `1`, duplicate `0`, conflict `1` |
| Two staged rows with same active content | `0 → 1` | `0 → 1` | inserted `1`, duplicate `1`, conflict `0` |

- Repeating verification preserved the same journal and sync counts.
- Concurrent verification committed one resolution set.
- Every accepted staging row received a non-`pending` resolution and a resolved entry ID.
- Manifest tampering returned `ErrIntegrityMismatch` and left journal and sync counts at `0 → 0`.
- Two completed photos with equal content hashes but distinct source filenames retained two Vault asset rows and two ordered filename mappings.
- `GET /v1/vault/migrations/{migrationId}/assets` exposes only verified mappings owned by the authenticated Vault and never exposes object keys or signed URLs.

## Apple Entitlement Evidence

- First legacy claim reserved the original purchase chain, assigned the authenticated `clovery_account_id` as the Apple account token, and then recorded the entitlement.
- Same-account replay skipped reservation and reassignment, reverified the transaction, and returned the current entitlement idempotently.
- Another account could not claim or record the same original transaction chain and received `ErrTransactionClaimed`.
- Failed Apple assignment did not create an entitlement.
- Empty `transaction_ids` performed zero transaction verifications, preserved current server entitlements, and marked entitlement reconciliation complete only after `Restore` returned successfully.
- `List`, individual verification, and legacy claim alone never marked the entitlement bootstrap stage complete.
- Apple verification unavailability kept the stage pending and recorded `apple_verification_temporarily_unavailable` as a retryable error.

## Bootstrap Evidence

- Migration creation attached its migration ID to the authenticated account bootstrap job.
- Successful migration verification marked migration complete; integrity failures marked `needs_attention`; transient failures kept the stage pending and incremented retry metadata.
- Vault checkpoint completion required `has_more=false` and a submitted cursor greater than or equal to the authenticated Vault's observed server maximum.
- A lower cursor or `has_more=true` kept the Vault stage pending.
- Completing identity, migration, entitlement, and Vault stages produced overall status `complete`.
- Sync changes created after the one-time Vault checkpoint did not reopen a completed bootstrap job.

## Commands and Exit Codes

```bash
DATABASE_URL='postgres://huao@localhost:5432/postgres?sslmode=disable' \
TEST_DATABASE_URL='postgres://huao@localhost:5432/postgres?sslmode=disable' \
GOCACHE=/private/tmp/clovery-go-build \
go test ./internal/migration ./internal/billing ./internal/bootstrapjob -count=1
# exit 0

GOCACHE=/private/tmp/clovery-go-build go test ./... -count=1
# exit 0

GOCACHE=/private/tmp/clovery-go-build go build ./cmd/api
# exit 0

GOCACHE=/private/tmp/clovery-go-build go test -race \
  ./internal/migration ./internal/http -run 'Migration|Resolution' -count=1
# exit 0

GOCACHE=/private/tmp/clovery-go-build go test -race \
  ./internal/billing ./internal/application/billingflow ./internal/http ./internal/contract ./cmd/api -count=1
# exit 0

GOCACHE=/private/tmp/clovery-go-build go test -race \
  ./internal/bootstrapjob ./internal/sync ./internal/http -run 'Bootstrap|Cursor|Checkpoint' -count=1
# exit 0

git diff --check
# exit 0
```

The generated `api` build artifact was removed after the build gate and is not tracked.
