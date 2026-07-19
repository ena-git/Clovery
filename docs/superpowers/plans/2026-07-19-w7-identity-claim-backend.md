# W7 Identity Claim and Account Bootstrap Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the production backend path that turns a verified but unbound Apple, Google, or Huawei identity into a one-time claim, atomically creates one Clovery account and vault, binds the identity, and exposes resumable account-bootstrap state.

**Architecture:** Keep Clovery account and vault creation inside PostgreSQL transactions. Federation verifies provider credentials first, then either returns the existing Clovery session or issues an opaque short-lived identity claim whose raw token is never stored. Claim registration locks and consumes that claim while creating the password credential, external identity, vault, and bootstrap job. A protected bootstrap API makes reconciliation resumable without allowing incomplete accounts into the application homepage.

**Tech Stack:** Go 1.24, Chi, PostgreSQL 16, pgx, existing Argon2id/session services, OpenAPI 3.1, Go unit and PostgreSQL integration tests.

---

## Scope, Dependencies, and Acceptance Boundary

This workflow implements sections 3, 5, and 9 of:

```text
docs/superpowers/specs/2026-07-19-legacy-account-inheritance-design.md
```

It depends only on migrations `000001` through `000015` and the existing auth/federation/session services. It does not implement diary deduplication, StoreKit reconciliation, or iOS UI; those are independently accepted in W8 and W9.

W7 is accepted when all of the following are true:

1. A bound external identity still returns the existing Clovery account, vault, and session.
2. An unbound verified identity returns HTTP `202` and a ten-minute one-time claim, not an account.
3. Claim registration creates exactly one account, one vault, one password credential, one external identity binding, and one bootstrap job in one transaction.
4. Retrying the same registration request is idempotent; replaying the claim with another request ID is rejected.
5. No path merges accounts by email, device ID, Apple relay email, or provider display name.
6. Bootstrap state can be read and resumed only by the authenticated account that owns it.

## Contract Decisions

### Federated completion

Bound identity, HTTP `200`:

```json
{
  "account_id": "11111111-1111-4111-8111-111111111111",
  "vault_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "access_token": "...",
  "refresh_token": "...",
  "access_token_expires_in": 900
}
```

The HTTP `200` body stays byte-contract compatible with the current `AuthSession` shape so already shipped clients are not broken. Only the new `202` claim response introduces a `status` discriminator.

Unbound verified identity, HTTP `202`:

```json
{
  "status": "identity_claim_required",
  "provider": "apple",
  "identity_claim_token": "opaque-base64url-token",
  "expires_in": 600
}
```

Claim registration extends `POST /v1/auth/accounts` without breaking plain registration:

```json
{
  "login_id": "userChosenID",
  "password": "at-least-8-characters",
  "recovery_method": "bound_identity",
  "identity_claim_token": "opaque-base64url-token",
  "registration_request_id": "8decaef4-af3a-4a23-b624-f6d6d2419566",
  "source_kind": "legacy_local",
  "device": {
    "device_id": "stable-installation-id",
    "platform": "ios",
    "name": "iPhone"
  }
}
```

Bootstrap state, `GET /v1/account/bootstrap`:

```json
{
  "status": "running",
  "source_kind": "legacy_local",
  "migration_id": null,
  "stages": {
    "identity": "complete",
    "migration": "pending",
    "entitlement": "pending",
    "vault": "pending"
  },
  "last_error_code": null,
  "retry_count": 0,
  "updated_at": "2026-07-19T10:00:00Z"
}
```

Allowed source kinds are `legacy_local`, `legacy_cloudkit`, and `new_install`. Allowed stage states are `pending`, `complete`, and `needs_attention`. Overall status is `pending`, `running`, `needs_attention`, or `complete`.

## Task 1: Add Identity Claim and Bootstrap Persistence

**Files:**
- Create: `v2/services/api/migrations/000016_identity_claim_bootstrap.up.sql`
- Create: `v2/services/api/migrations/000016_identity_claim_bootstrap.down.sql`
- Create: `v2/services/api/internal/database/identity_claim_bootstrap_migration_test.go`
- Modify: `v2/contracts/openapi/openapi.yaml`

- [ ] **Step 1: Write the migration contract test first**

Create a table-driven test that reads the migration files and asserts the required tables, uniqueness, ownership keys, expiry index, and rollback statements are present:

```go
func TestIdentityClaimBootstrapMigrationContract(t *testing.T) {
    up := readMigration(t, "000016_identity_claim_bootstrap.up.sql")
    for _, fragment := range []string{
        "CREATE TABLE identity_claims",
        "token_sha256 CHAR(64) NOT NULL UNIQUE",
        "login_intent_id UUID NOT NULL UNIQUE",
        "CREATE TABLE account_bootstrap_jobs",
        "account_id UUID PRIMARY KEY",
        "vault_id UUID NOT NULL UNIQUE",
        "CREATE INDEX identity_claims_expires_at_idx",
    } {
        if !strings.Contains(up, fragment) {
            t.Fatalf("migration missing %q", fragment)
        }
    }
}
```

If the existing database test package already contains a `readMigration` helper, reuse it instead of duplicating it.

- [ ] **Step 2: Run the focused test and observe the missing migration failure**

Run:

```bash
cd /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/v2/services/api
GOCACHE=/private/tmp/clovery-go-build go test ./internal/database -run IdentityClaimBootstrap
```

Expected: failure because migration `000016_identity_claim_bootstrap` does not exist.

- [ ] **Step 3: Create the forward migration**

Use database-native checks rather than application-only validation:

```sql
CREATE TABLE identity_claims (
    id UUID PRIMARY KEY,
    token_sha256 CHAR(64) NOT NULL UNIQUE,
    provider TEXT NOT NULL CHECK (provider IN ('apple', 'google', 'huawei')),
    issuer TEXT NOT NULL,
    subject TEXT NOT NULL,
    login_intent_id UUID NOT NULL UNIQUE REFERENCES federation_intents(id) ON DELETE RESTRICT,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    consumed_by_account_id UUID REFERENCES clovery_accounts(id) ON DELETE RESTRICT,
    registration_request_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK ((consumed_at IS NULL) = (consumed_by_account_id IS NULL)),
    CHECK ((consumed_at IS NULL) = (registration_request_id IS NULL))
);

CREATE INDEX identity_claims_expires_at_idx
    ON identity_claims (expires_at)
    WHERE consumed_at IS NULL;

CREATE INDEX identity_claims_identity_idx
    ON identity_claims (provider, issuer, subject);

CREATE TABLE account_bootstrap_jobs (
    account_id UUID PRIMARY KEY REFERENCES clovery_accounts(id) ON DELETE CASCADE,
    vault_id UUID NOT NULL UNIQUE REFERENCES vaults(id) ON DELETE CASCADE,
    source_kind TEXT NOT NULL CHECK (source_kind IN ('legacy_local', 'legacy_cloudkit', 'new_install')),
    migration_id UUID REFERENCES vault_migrations(id) ON DELETE SET NULL,
    identity_state TEXT NOT NULL DEFAULT 'complete'
        CHECK (identity_state IN ('pending', 'complete', 'needs_attention')),
    migration_state TEXT NOT NULL DEFAULT 'pending'
        CHECK (migration_state IN ('pending', 'complete', 'needs_attention')),
    entitlement_state TEXT NOT NULL DEFAULT 'pending'
        CHECK (entitlement_state IN ('pending', 'complete', 'needs_attention')),
    vault_state TEXT NOT NULL DEFAULT 'pending'
        CHECK (vault_state IN ('pending', 'complete', 'needs_attention')),
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'running', 'needs_attention', 'complete')),
    last_error_code TEXT,
    retry_count INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

Do not add email or device columns to `identity_claims`. Do not persist the raw token.

- [ ] **Step 4: Create the rollback migration**

Drop child state before claim state:

```sql
DROP TABLE IF EXISTS account_bootstrap_jobs;
DROP TABLE IF EXISTS identity_claims;
```

- [ ] **Step 5: Update the OpenAPI schemas and responses**

Add:

- `IdentityClaimRequiredResponse`
- `AccountBootstrapResponse`
- `AccountBootstrapResumeRequest`
- optional claim fields on `CreateAccountRequest`
- `202` on federated completion
- protected `GET /v1/account/bootstrap`
- protected `POST /v1/account/bootstrap/resume`

Express the registration rule in the schema description: `identity_claim_token` and `registration_request_id` must be supplied together, and `recovery_method` is `bound_identity` for claim registration.

- [ ] **Step 6: Run database and OpenAPI contract tests**

Run:

```bash
GOCACHE=/private/tmp/clovery-go-build go test ./internal/database ./internal/contract
```

Expected: both packages pass.

- [ ] **Step 7: Commit the persistence contract**

```bash
git add v2/services/api/migrations/000016_identity_claim_bootstrap.* \
  v2/services/api/internal/database/identity_claim_bootstrap_migration_test.go \
  v2/contracts/openapi/openapi.yaml
git commit -m "feat(auth): add identity claim persistence"
```

## Task 2: Implement One-Time Identity Claims

**Files:**
- Create: `v2/services/api/internal/identityclaim/types.go`
- Create: `v2/services/api/internal/identityclaim/token.go`
- Create: `v2/services/api/internal/identityclaim/repository.go`
- Create: `v2/services/api/internal/identityclaim/service.go`
- Create: `v2/services/api/internal/identityclaim/service_test.go`
- Create: `v2/services/api/internal/identityclaim/postgres_integration_test.go`

- [ ] **Step 1: Write service tests for issuance and validation**

Cover these cases with a fake clock and deterministic token source:

```text
issue stores only SHA-256 digest
issue returns the raw opaque token once
consume accepts a valid unconsumed claim
consume rejects an expired claim
consume rejects an already-consumed claim
same request ID returns the previous account and vault
different request ID returns identity_claim_consumed
provider, issuer, and subject remain unchanged
```

The raw token type must not implement `fmt.Stringer` and must never be included in errors.

- [ ] **Step 2: Run the focused tests and observe compilation failure**

```bash
GOCACHE=/private/tmp/clovery-go-build go test ./internal/identityclaim
```

Expected: package or symbols do not exist.

- [ ] **Step 3: Define explicit domain types and errors**

Use typed values rather than map payloads:

```go
type Identity struct {
    Provider string
    Issuer   string
    Subject  string
    IntentID string
}

type IssuedClaim struct {
    Token     string
    Provider  string
    ExpiresIn time.Duration
}

var (
    ErrInvalidClaim  = errors.New("invalid identity claim")
    ErrExpiredClaim  = errors.New("expired identity claim")
    ErrConsumedClaim = errors.New("consumed identity claim")
)
```

Generate 32 random bytes, encode with unpadded base64url, and store `hex(SHA-256(rawToken))`.

- [ ] **Step 4: Implement repository transactions**

`Issue` inserts provider, issuer, subject, intent, digest, and expiry. `LockForRegistration` uses:

```sql
SELECT id, provider, issuer, subject, expires_at,
       consumed_at, consumed_by_account_id, registration_request_id
FROM identity_claims
WHERE token_sha256 = $1
FOR UPDATE;
```

Keep claim locking available to the account repository through a transaction-scoped method; do not consume the claim in a separate transaction.

- [ ] **Step 5: Add PostgreSQL integration coverage**

Use the repository's existing `TEST_DATABASE_URL` convention. Prove that concurrent attempts cannot both consume a claim and that the database contains only a digest, not the raw token.

- [ ] **Step 6: Run focused and race tests**

```bash
GOCACHE=/private/tmp/clovery-go-build go test -race ./internal/identityclaim
```

Expected: all identity claim tests pass; integration tests skip only when `TEST_DATABASE_URL` is absent.

- [ ] **Step 7: Commit the domain service**

```bash
git add v2/services/api/internal/identityclaim
git commit -m "feat(auth): issue one-time identity claims"
```

## Task 3: Return a Claim for Verified Unbound Federation

**Files:**
- Modify: `v2/services/api/internal/auth/federation.go`
- Modify: `v2/services/api/internal/auth/federation_login.go`
- Modify: `v2/services/api/internal/auth/federation_service_test.go`
- Modify: `v2/services/api/internal/application/identityflow/types.go`
- Modify: `v2/services/api/internal/application/identityflow/federated_flow.go`
- Modify: `v2/services/api/internal/application/identityflow/service_test.go`
- Modify: `v2/services/api/internal/http/federation_contract.go`
- Modify: `v2/services/api/internal/http/federation_application_adapter.go`
- Modify: `v2/services/api/internal/http/federation_handler.go`
- Modify: `v2/services/api/internal/http/identity_handler_test.go`
- Modify: `v2/services/api/internal/http/identity_application_adapter_test.go`
- Modify: `v2/services/api/cmd/api/identity_bootstrap.go`
- Modify: `v2/services/api/cmd/api/bootstrap.go`
- Modify: `v2/services/api/cmd/api/bootstrap_test.go`

- [ ] **Step 1: Change tests to require a typed federation resolution**

Replace the current unbound-identity error expectation with:

```go
type FederatedLoginResolution struct {
    Identity FederatedIdentityKey
    Account  *FederatedAccount
}
```

Test that a bound result has `Account != nil`, while an unbound verified result has the stable provider/issuer/subject and `Account == nil` without returning `ErrFederatedIdentityNotBound`.

- [ ] **Step 2: Run auth tests and verify they fail**

```bash
GOCACHE=/private/tmp/clovery-go-build go test ./internal/auth -run Federated
```

Expected: the old implementation still returns `ErrFederatedIdentityNotBound`.

- [ ] **Step 3: Return verified identity resolution from auth**

Keep all existing intent consumption, nonce verification, provider verification, issuer validation, and subject extraction. Change only the final lookup behavior:

```go
account, err := service.identities.FindAccountByIdentity(ctx, identity)
if errors.Is(err, ErrFederatedIdentityNotBound) {
    return FederatedLoginResolution{Identity: identity}, nil
}
if err != nil {
    return FederatedLoginResolution{}, err
}
return FederatedLoginResolution{Identity: identity, Account: &account}, nil
```

Never use the verified email claim for account lookup.

- [ ] **Step 4: Add claim issuance to the application flow**

Define a small dependency:

```go
type IdentityClaimIssuer interface {
    Issue(context.Context, identityclaim.Identity) (identityclaim.IssuedClaim, error)
}
```

`CompleteFederatedLogin` returns one of two mutually exclusive results:

```go
type FederatedCompletion struct {
    Session *SessionResult
    Claim   *IdentityClaimResult
}
```

Assert in tests that exactly one field is non-nil.

- [ ] **Step 5: Map the union to HTTP `200` or `202`**

The handler must use `writeJSON` exactly once:

```go
if result.Claim != nil {
    writeJSON(responseWriter, http.StatusAccepted, identityClaimRequiredResponse{
        Status:             "identity_claim_required",
        Provider:           result.Claim.Provider,
        IdentityClaimToken: result.Claim.Token,
        ExpiresIn:          int(result.Claim.ExpiresIn.Seconds()),
    })
    return
}
writeJSON(responseWriter, http.StatusOK, authSessionFromIdentityFlow(*result.Session))
```

Add malformed, expired-intent, provider-verification, bound, and unbound handler tests. The old public `identity_not_bound` response must no longer be returned by login completion.

- [ ] **Step 6: Wire the claim service in `cmd/api`**

Construct one PostgreSQL claim repository and inject the same claim service into federation completion and claim registration. Do not construct independent in-memory services in handlers.

- [ ] **Step 7: Run the affected packages**

```bash
GOCACHE=/private/tmp/clovery-go-build go test \
  ./internal/auth \
  ./internal/application/identityflow \
  ./internal/http \
  ./cmd/api
```

Expected: all affected packages pass.

- [ ] **Step 8: Commit federation claim responses**

```bash
git add v2/services/api/internal/auth \
  v2/services/api/internal/application/identityflow \
  v2/services/api/internal/http \
  v2/services/api/cmd/api
git commit -m "feat(auth): return claims for unbound identities"
```

## Task 4: Atomically Register a Claimed Clovery Account

**Files:**
- Modify: `v2/services/api/internal/http/auth_contract.go`
- Modify: `v2/services/api/internal/http/auth_account_handler.go`
- Modify: `v2/services/api/internal/http/auth_application_adapter.go`
- Modify: `v2/services/api/internal/http/auth_handler_test.go`
- Modify: `v2/services/api/internal/application/authflow/types.go`
- Modify: `v2/services/api/internal/application/authflow/register.go`
- Modify: `v2/services/api/internal/application/authflow/service.go`
- Modify: `v2/services/api/internal/application/authflow/service_test.go`
- Create: `v2/services/api/internal/account/claimed_create_repository.go`
- Create: `v2/services/api/internal/account/claimed_create_repository_test.go`
- Modify: `v2/services/api/cmd/api/bootstrap.go`

- [ ] **Step 1: Add failing request validation tests**

Cover:

```text
plain registration remains compatible
claim token without registration request ID is rejected
registration request ID without claim token is rejected
claim registration requires recovery_method=bound_identity
plain registration rejects recovery_method=bound_identity
source_kind is required for claim registration
password still enforces 8..256 characters
```

Use the generic code `invalid_auth_request` for malformed field combinations so the response does not reveal claim state.

- [ ] **Step 2: Add failing transactional repository tests**

The PostgreSQL test must assert row counts after success and after injected failure:

```text
success: clovery_accounts=1, vaults=1, account_login_ids=1, password_credentials=1,
         external_identities=1, account_bootstrap_jobs=1, consumed claims=1
injected failure: every count remains 0 and claim remains unconsumed
```

Also assert:

- same token + same `registration_request_id` returns the original account/vault;
- same token + different request ID returns `ErrConsumedClaim`;
- duplicate external identity cannot produce a second account;
- duplicate custom CloveryID returns the existing generic unavailable error.

- [ ] **Step 3: Run focused tests and verify failure**

```bash
GOCACHE=/private/tmp/clovery-go-build go test ./internal/account ./internal/application/authflow ./internal/http -run 'Claim|CreateAccount'
```

Expected: new claim-registration cases fail or do not compile.

- [ ] **Step 4: Extend command and HTTP models**

Use pointer fields only for optional claim data:

```go
type CreateAccountCommand struct {
    LoginID              string
    Password             string
    RecoveryMethod       string
    IdentityClaimToken   *string
    RegistrationRequestID *string
    SourceKind           *string
    Device               DeviceCommand
}
```

Normalize `registration_request_id` into a UUID before entering the repository. Do not accept client-provided account or vault IDs.

- [ ] **Step 5: Implement one repository transaction**

Inside `CreateClaimedAccount`:

1. begin transaction;
2. lock claim by token digest;
3. check expiry, consumption, and idempotency;
4. validate the external identity is still unbound;
5. insert account, normalized CloveryID, password hash, vault, and external identity;
6. insert bootstrap job with `identity_state='complete'`, entitlement/vault pending, and migration pending for `legacy_local`/`legacy_cloudkit` or complete for `new_install`;
7. mark the claim consumed with account and request ID;
8. commit;
9. return account and vault IDs.

Reuse existing account/vault insertion helpers by extracting transaction-scoped methods from `create_repository.go`; do not duplicate SQL across plain and claim registration.

- [ ] **Step 6: Keep session issuance outside the database transaction**

After commit, issue the normal access/refresh session. If session issuance fails, retrying the same request ID must recover the existing account/vault and issue a fresh session without creating rows. Claim registration returns no recovery-code list because the account already has password plus a verified bound identity.

- [ ] **Step 7: Run transaction, handler, and race tests**

```bash
GOCACHE=/private/tmp/clovery-go-build go test -race \
  ./internal/account \
  ./internal/application/authflow \
  ./internal/http
```

Expected: all packages pass; PostgreSQL cases skip only without `TEST_DATABASE_URL`.

- [ ] **Step 8: Commit claim registration**

```bash
git add v2/services/api/internal/account \
  v2/services/api/internal/application/authflow \
  v2/services/api/internal/http \
  v2/services/api/cmd/api
git commit -m "feat(auth): create claimed accounts atomically"
```

## Task 5: Expose Resumable Account Bootstrap State

**Files:**
- Create: `v2/services/api/internal/bootstrapjob/types.go`
- Create: `v2/services/api/internal/bootstrapjob/repository.go`
- Create: `v2/services/api/internal/bootstrapjob/service.go`
- Create: `v2/services/api/internal/bootstrapjob/service_test.go`
- Create: `v2/services/api/internal/bootstrapjob/postgres_integration_test.go`
- Create: `v2/services/api/internal/http/bootstrap_contract.go`
- Create: `v2/services/api/internal/http/bootstrap_application_adapter.go`
- Create: `v2/services/api/internal/http/bootstrap_handler.go`
- Create: `v2/services/api/internal/http/bootstrap_handler_test.go`
- Modify: `v2/services/api/internal/http/router.go`
- Modify: `v2/services/api/cmd/api/bootstrap.go`
- Modify: `v2/services/api/cmd/api/bootstrap_test.go`
- Modify: `v2/contracts/openapi/openapi.yaml`

- [ ] **Step 1: Write state transition tests**

Use a table to enforce:

```text
pending -> running
running -> complete only when all stages are complete
any stage -> needs_attention with a stable error code
needs_attention -> running on resume, preserving completed stages
resume increments retry_count
one account cannot read or mutate another account's job
```

Invalid backward transitions such as `complete -> pending` must return a domain error.

- [ ] **Step 2: Run focused tests and observe failure**

```bash
GOCACHE=/private/tmp/clovery-go-build go test ./internal/bootstrapjob ./internal/http -run Bootstrap
```

Expected: missing package and routes.

- [ ] **Step 3: Implement repository and service**

Repository reads and updates by authenticated `account_id`, not by arbitrary job IDs. `Resume` clears `last_error_code`, increments retry count, preserves `migration_id`, and changes only `needs_attention` to `running`.

Provide internal methods for later workflows:

```go
MarkMigration(ctx context.Context, accountID, migrationID string, state StageState, errorCode *string) error
MarkEntitlement(ctx context.Context, accountID string, state StageState, errorCode *string) error
MarkVault(ctx context.Context, accountID string, state StageState, errorCode *string) error
```

Each method recalculates overall status in the same transaction.

- [ ] **Step 4: Add protected HTTP routes**

Register under the existing auth middleware:

```go
protected.Get("/v1/account/bootstrap", handler.get)
protected.Post("/v1/account/bootstrap/resume", handler.resume)
```

Derive account ID only from auth context. Return `404 bootstrap_not_found` only for authenticated accounts created before this migration; the iOS workflow will call `resume` to create a compatible job for those accounts.

- [ ] **Step 5: Make resume compatible with existing accounts**

For an account with no job, `POST /resume` verifies the authenticated account/vault relation and creates one job using the provided `source_kind`. `new_install` starts with migration complete; legacy sources start with migration pending. For an existing job, it ignores a conflicting source kind and returns the stored source to prevent client-driven reclassification.

- [ ] **Step 6: Run API and integration tests**

```bash
GOCACHE=/private/tmp/clovery-go-build go test -race \
  ./internal/bootstrapjob \
  ./internal/http \
  ./cmd/api \
  ./internal/contract
```

Expected: all packages pass and protected routes return `401` without a session.

- [ ] **Step 7: Commit bootstrap APIs**

```bash
git add v2/services/api/internal/bootstrapjob \
  v2/services/api/internal/http \
  v2/services/api/cmd/api \
  v2/contracts/openapi/openapi.yaml
git commit -m "feat(account): add resumable bootstrap state"
```

## Task 6: Verify W7 as an Independent Deliverable

**Files:**
- Modify if generated by existing tooling: `v2/contracts/openapi/openapi.yaml`
- Create: `docs/superpowers/verification/2026-07-19-w7-identity-claim-backend.md`

- [ ] **Step 1: Apply migrations to a disposable PostgreSQL database**

```bash
cd /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/v2
docker compose up -d postgres
cd services/api
TEST_DATABASE_URL='postgres://clovery:clovery@localhost:5432/clovery_test?sslmode=disable' \
  go test ./internal/identityclaim ./internal/account ./internal/bootstrapjob
```

Expected: transaction and concurrency integration tests pass.

- [ ] **Step 2: Run the complete Go quality gate**

```bash
GOCACHE=/private/tmp/clovery-go-build go test ./...
GOCACHE=/private/tmp/clovery-go-build go build ./cmd/api
gofmt -w internal/identityclaim internal/bootstrapjob internal/account \
  internal/application/authflow internal/application/identityflow internal/http cmd/api
git diff --check
```

Expected: tests and build exit `0`; `git diff --check` prints nothing.

- [ ] **Step 3: Record reproducible acceptance evidence**

The verification document must include:

- tested commit SHA;
- migration apply/rollback result;
- bound identity response status;
- unbound identity `202` redacted response;
- idempotent registration row counts;
- concurrent replay result;
- full Go test/build commands and exit codes;
- confirmation that no raw claim token appears in database or logs.

- [ ] **Step 4: Commit and push the accepted workflow**

```bash
git add docs/superpowers/verification/2026-07-19-w7-identity-claim-backend.md
git commit -m "test(auth): verify identity claim workflow"
git push origin codex/swift-auth-foundation
```

Expected: the remote branch contains all W7 commits and the working tree is clean.

## W7 Non-Goals

- Do not create accounts directly from Apple, Google, or Huawei subjects.
- Do not merge by email.
- Do not upload or delete legacy diary data.
- Do not decide App Store entitlement ownership from Apple Sign in.
- Do not expose Passkey as a first-screen provider button.
- Do not make homepage readiness a client-only boolean; W9 must consume the server bootstrap state.
