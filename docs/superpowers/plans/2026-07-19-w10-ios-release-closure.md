# W10 iOS 1.1.0 Release Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every remaining compliance, database, automated-test, simulator, physical-device, StoreKit, TestFlight, App Store, GitHub, rollback, and evidence gate required to publish Clovery iOS `1.1.0 (15)` as a safe upgrade over the existing `1.0.3 (14)` release.

**Architecture:** Treat release as a coordinated backend-first migration. Production-compatible database migrations and Go services deploy before the App Store binary. The iOS archive keeps all existing App Store identities and entitlements while adding account deletion and legal access required by account creation. Automated gates run before any physical-device work; true-device upgrade and cross-device inheritance run only after W9 is complete and before Flutter starts. Release evidence contains no credentials, diary content, stable user IDs, or transaction payloads.

**Tech Stack:** Go 1.24, PostgreSQL 16, Docker Compose, Swift 5, SwiftUI, StoreKit 2, XCTest, Xcode Archive/Organizer, App Store Connect, TestFlight, GitHub Actions, `git`, `gh`, shell release scripts.

---

## Dependency and Release Order

W10 starts only after W7, W8, and W9 verification documents are complete. The immutable order is:

```text
W7 identity/account backend
  -> W8 migration/entitlement backend
  -> backend staging and production-compatible database migration
  -> W9 native iOS completion and simulator gate
  -> W10 physical-device upgrade + Sandbox + TestFlight
  -> App Store phased release
  -> Flutter W3 may begin
```

Do not begin Flutter while any W10 physical-device or TestFlight P0 gate is incomplete.

## Release Identity

```text
Marketing version: 1.1.0
Build number:      15
Main bundle ID:    com.clovery.app
Widget bundle ID:  com.clovery.app.CloveryWidget
Team ID:           M92TBSSR2R
App Group:         group.com.clovery.app
iCloud container:  iCloud.com.clovery.app
Product ID:        com.clovery.app.board.lifetime
Minimum iOS:       16.0
```

No task may replace the bundle ID, App Group, iCloud container, StoreKit product ID, or signing team. Version `1.1.0` is a feature release because it introduces mandatory Clovery accounts and cross-device account inheritance; it is not shipped as another invisible patch.

## Official Apple Gates

The release checklist must link these current Apple references:

- Account creation requires in-app initiation of account deletion: `https://developer.apple.com/support/offering-account-deletion-in-your-app/`
- App Store privacy requires a public privacy-policy URL and accurate data-use answers: `https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy`
- App Store Connect in-app purchase setup/status: `https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-statuses/`
- Sandbox and TestFlight purchase testing: `https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox`

## Release Blocking Severity

```text
P0: data loss, duplicate/incorrect account, cross-account Vault or entitlement,
    paid user locked, account deletion unavailable, crash, failed upgrade,
    production migration without restorable backup
P1: login provider unavailable, photo save failure, unreadable Dynamic Type,
    retry cannot recover, privacy/StoreKit metadata incomplete
P2: cosmetic mismatch that does not block operation
```

Any open P0 or P1 blocks submission. P2 requires an owner and follow-up version before release approval.

## Task 1: Add In-App Account Deletion and Public Legal Access

**Files:**
- Create: `v2/services/api/legal/privacy.zh-CN.html`
- Create: `v2/services/api/legal/terms.zh-CN.html`
- Create: `v2/services/api/internal/http/legal_handler.go`
- Create: `v2/services/api/internal/http/legal_handler_test.go`
- Modify: `v2/services/api/internal/http/router.go`
- Modify: `v2/contracts/openapi/openapi.yaml`
- Create: `Clovery/Features/Account/Data/AccountManagementAPI.swift`
- Create: `Clovery/Features/Account/Presentation/AccountSecurityView.swift`
- Create: `Clovery/Features/Account/Presentation/DeleteAccountConfirmationView.swift`
- Modify: `Clovery/Features/Authentication/Presentation/SignUpView.swift`
- Modify: `Clovery/WebView.swift`
- Modify: `Clovery/Clover Diary.html`
- Modify: `Clovery.xcodeproj/project.pbxproj`
- Create: `CloveryTests/AccountManagementAPITests.swift`
- Create: `CloveryTests/AccountSecurityViewModelTests.swift`
- Modify: `CloveryTests/WebBridgeContractTests.swift`

- [ ] **Step 1: Write backend public legal-page tests**

Require unauthenticated routes:

```text
GET /v1/legal/privacy -> 200 text/html; charset=utf-8
GET /v1/legal/terms   -> 200 text/html; charset=utf-8
```

Tests assert both pages include effective date `2026-07-19`, operator/contact section using the operational mailbox `support@clovery.cn`, account data, diary/photo storage, provider identity, StoreKit transaction handling, retention/deletion, cross-device sync, security, minors, and policy update sections. They must not contain placeholder domains, `TODO`, or sample contact addresses. Release is blocked until the mailbox can receive and answer a test message.

- [ ] **Step 2: Draft and legally review Chinese documents**

Use the production URLs:

```text
https://api.clovery.cn/v1/legal/privacy
https://api.clovery.cn/v1/legal/terms
```

The implementation team drafts factual content matching actual W7-W9 behavior. Before App Store submission, the product owner records legal/privacy approval in the release evidence. Do not claim data is end-to-end encrypted unless the implemented vault cryptography proves it.

- [ ] **Step 3: Write account-management API tests**

Typed methods:

```swift
func summary() async throws -> AccountSummary
func requestDeletion() async throws -> AccountDeletionRequest
```

Assert authenticated `GET /v1/account` and `POST /v1/account/deletion-requests`, generic safe errors, and immediate local logout after an accepted deletion request. Never send account ID in the body.

- [ ] **Step 4: Write deletion view-model tests**

Require:

```text
account security shows CloveryID and linked provider names without subjects
delete action requires explicit second confirmation
confirmation copy states account, Vault, photos, and server rights will be scheduled for deletion
accepted request clears session and account-scoped entitlement cache
failed request keeps the user logged in and shows retry
offline state cannot falsely report deletion success
```

- [ ] **Step 5: Run focused tests and observe missing UI/routes**

```bash
cd /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/v2/services/api
GOCACHE=/private/tmp/clovery-go-build go test ./internal/http -run Legal
cd ../../../
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/AccountManagementAPITests \
  -only-testing:CloveryTests/AccountSecurityViewModelTests \
  -only-testing:CloveryTests/WebBridgeContractTests test
```

Expected: legal handler and account UI tests fail before implementation.

- [ ] **Step 6: Implement public legal routes safely**

Embed or read immutable HTML from the binary and set CSP/security headers. Do not make database or authentication calls. Add cache headers with a short max age so policy updates deploy predictably.

- [ ] **Step 7: Implement account security UI in Clovery style**

Add an “账户与安全” item to the existing settings page in `Clover Diary.html`. It posts an `accountSecurity` WebKit message. `WebView` forwards that event to `ApplicationRootView`, which presents a native sheet. Use existing colors, dashed cards, Chinese copy, and `.cloveryFont`; do not redesign the diary settings page.

The delete confirmation button remains disabled until the user enters the displayed CloveryID exactly. On acceptance, clear session/caches and return to authentication. The backend deletion workflow remains the authority for retained-data deletion.

- [ ] **Step 8: Add privacy and terms acknowledgement to registration**

Below the registration action, add concise Chinese text with tappable in-app Safari links to the two production URLs. The acceptance checkbox starts unchecked and registration remains disabled until the user explicitly accepts. Do not store the checkbox as authorization for unrelated processing.

- [ ] **Step 9: Run Go/iOS focused tests**

```bash
cd v2/services/api
GOCACHE=/private/tmp/clovery-go-build go test ./internal/http ./internal/contract
cd ../../..
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/AccountManagementAPITests \
  -only-testing:CloveryTests/AccountSecurityViewModelTests \
  -only-testing:CloveryTests/WebBridgeContractTests test
```

Expected: all selected tests pass.

- [ ] **Step 10: Commit compliance access**

```bash
git add v2/services/api/legal v2/services/api/internal/http v2/contracts/openapi/openapi.yaml \
  Clovery/Features/Account Clovery/Features/Authentication/Presentation/SignUpView.swift \
  Clovery/WebView.swift 'Clovery/Clover Diary.html' CloveryTests \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat(account): add deletion and legal access"
```

## Task 2: Lock Version, Signing, Privacy, and Repository Hygiene

**Files:**
- Modify: `Clovery.xcodeproj/project.pbxproj`
- Modify: `scripts/verify-ios-release-config.sh`
- Modify: `Tests/IOSReleaseIdentityTests.sh`
- Create: `scripts/verify-repository-hygiene.sh`
- Create: `Tests/RepositoryHygieneTests.sh`
- Modify: `.gitignore`
- Modify: `.github/workflows/verify-ios-v1.yml`
- Create: `docs/release/ios-1.1.0-acceptance.md`
- Create: `docs/release/1.1.0-ios-release.md`

- [ ] **Step 1: Change release identity tests before project values**

Update expectations to `1.1.0 (15)` for app and widget. Add checks for:

```text
com.apple.developer.applesignin
group.com.clovery.app
iCloud.com.clovery.app
NSPhotoLibraryAddUsageDescription
PrivacyInfo.xcprivacy included in app resources
production API HTTPS and not staging
legal URLs use HTTPS and resolve to api.clovery.cn
Release scheme does not use Clovery.storekit
```

- [ ] **Step 2: Run identity tests and observe version failure**

```bash
Tests/IOSReleaseIdentityTests.sh
```

Expected: current project still reports `1.0.3 (14)`.

- [ ] **Step 3: Update app and widget versions together**

Change only release identity values to `MARKETING_VERSION = 1.1.0` and `CURRENT_PROJECT_VERSION = 15`. Keep test bundle versions irrelevant to App Store identity.

- [ ] **Step 4: Add repository hygiene tests**

The script fails when:

- tracked files include `.env`, certificates, provisioning profiles, API keys, StoreKit JWS, migration bundles, user photos, XCResult, archives, or DerivedData;
- unignored generated directories exceed 100 MB;
- tracked files exceed 25 MB unless listed in a reviewed static-web allowlist;
- `git status` contains generated build output after verification;
- release evidence includes email, account UUID, device UDID, transaction ID, recovery code, diary text, or complete SHA.

Do not delete tracked source/vendor assets merely to reduce size. Delete only reproducible local build output after evidence extraction.

- [ ] **Step 5: Extend `.gitignore`**

Add:

```gitignore
*.xcresult
*.xcarchive
*.ipa
*.mobileprovision
*.p8
*.p12
build/release-evidence/
Documents/CloveryMigration/
```

Do not ignore source migrations, tests, legal pages, release checklists, or verification summaries.

- [ ] **Step 6: Update CI and release docs**

Rename user-facing gate labels from “V1 1.0.3” to “iOS 1.1.0 account upgrade”. CI runs repository hygiene, Go tests/build, Swift tests, HTML/bridge tests, privacy manifest checks, and Release simulator build. Secrets are referenced by GitHub Actions secret names only.

- [ ] **Step 7: Run identity and hygiene checks**

```bash
chmod +x scripts/verify-repository-hygiene.sh Tests/RepositoryHygieneTests.sh
Tests/IOSReleaseIdentityTests.sh
Tests/RepositoryHygieneTests.sh
scripts/verify-repository-hygiene.sh
git diff --check
```

Expected: all commands exit `0`.

- [ ] **Step 8: Commit release identity**

```bash
git add Clovery.xcodeproj/project.pbxproj scripts Tests .gitignore \
  .github/workflows/verify-ios-v1.yml docs/release
git commit -m "chore(release): prepare iOS 1.1.0 identity"
```

## Task 3: Rehearse Database Backup, Upgrade, Rollback, and Reapply

**Files:**
- Create: `v2/scripts/backup-before-account-bootstrap.sh`
- Create: `v2/scripts/verify-account-bootstrap-migrations.sh`
- Create: `v2/docs/release/ios-1.1.0-database-runbook.md`
- Create: `v2/docs/release/ios-1.1.0-rollback-runbook.md`
- Modify: `v2/docs/release/backend-deployment.md`
- Create: `v2/services/api/internal/database/account_upgrade_rehearsal_test.go`

- [ ] **Step 1: Write database rehearsal tests**

On a disposable schema, seed realistic pre-W7 data:

```text
existing Clovery account/vault/password
bound Apple identity
unbound external identity intent
journal entries with and without migration provenance
legacy migration staging rows
active and revoked Apple entitlements
```

Apply `000016` and `000017`, assert old rows and foreign keys remain, roll back both, assert the pre-upgrade schema/data remains readable, then reapply and assert idempotent application.

- [ ] **Step 2: Run rehearsal test and observe missing scripts/test fixtures**

```bash
cd /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/v2/services/api
DATABASE_URL='postgres://clovery:clovery@localhost:5432/clovery_test?sslmode=disable' \
  GOCACHE=/private/tmp/clovery-go-build \
  go test ./internal/database -run AccountUpgradeRehearsal
```

Expected: test fails before the rehearsal fixture is implemented.

- [ ] **Step 3: Implement encrypted, restorable backup script**

The script requires an explicit database URL and output directory outside Git, runs `pg_dump --format=custom --no-owner`, computes a local SHA-256, and records PostgreSQL/server migration versions. It refuses an output path inside the repository and sets file mode `0600`. Encryption/upload to the operator's approved backup storage happens outside Git using deployment secrets.

- [ ] **Step 4: Implement migration verification script**

Verify:

```text
schema version is exactly 17
identity_claims stores no raw-token column
account_bootstrap_jobs account/vault uniqueness exists
migration resolution constraints/indexes exist
all pre-existing account/vault/entitlement row counts match baseline
no orphan external identities or vaults
```

- [ ] **Step 5: Rehearse restore into a second database**

Run in staging operations environment:

```bash
v2/scripts/backup-before-account-bootstrap.sh "$STAGING_DATABASE_URL" "$SECURE_EVIDENCE_DIR"
createdb clovery_restore_rehearsal
pg_restore --clean --if-exists --no-owner \
  --dbname "$RESTORE_DATABASE_URL" "$SECURE_EVIDENCE_DIR/clovery-before-1.1.0.dump"
```

Expected: restore exits `0`, baseline counts and sampled relationships match. Record only aggregate PASS in Git.

- [ ] **Step 6: Rehearse service rollback without destructive DB downgrade**

Because `000016` and `000017` are additive, the preferred rollback is deploying the previous API binary while leaving compatible columns/tables in place and disabling new migration writes. SQL down migration is practiced only on disposable staging restore, never as the first production rollback action.

- [ ] **Step 7: Run database package tests**

```bash
DATABASE_URL='postgres://clovery:clovery@localhost:5432/clovery_test?sslmode=disable' \
  GOCACHE=/private/tmp/clovery-go-build \
  go test ./internal/database ./internal/identityclaim ./internal/migration ./internal/billing
```

Expected: all enabled tests pass.

- [ ] **Step 8: Commit operational runbooks**

```bash
git add v2/scripts v2/docs/release v2/docs/release/backend-deployment.md \
  v2/services/api/internal/database/account_upgrade_rehearsal_test.go
git commit -m "ops(database): rehearse account upgrade backup"
```

## Task 4: Run Staging Account-Inheritance and Billing Scenarios

**Files:**
- Create: `v2/scripts/smoke-account-inheritance.sh`
- Create: `v2/scripts/smoke-legacy-entitlement.sh`
- Create: `v2/docs/release/ios-1.1.0-staging-acceptance.md`
- Modify: `v2/infra/staging/.env.example`

- [ ] **Step 1: Add non-secret staging configuration keys**

Document names only:

```text
IDENTITY_CLAIM_TTL_SECONDS=600
MIGRATION_WRITES_ENABLED=true
APPLE_BILLING_BUNDLE_ID=com.clovery.app
APPLE_BILLING_PRODUCT_IDS=com.clovery.app.board.lifetime
APPLE_SERVER_NOTIFICATION_URL production/sandbox configured externally
```

Keep private keys, issuer IDs, key IDs, webhook secrets, database URLs, and test accounts out of Git.

- [ ] **Step 2: Implement redacted API smoke scripts**

Scripts use environment tokens and temporary files under the secure evidence directory. They print only scenario names and PASS/FAIL. Required scenarios:

```text
bound Apple -> original account/vault
unbound Apple -> 202 claim, no account
claim registration -> one account/vault/binding/job
same request retry -> same account/vault
claim replay with another request -> conflict
plain Clovery registration/login -> bootstrap job
same diary migration twice -> one result
different-ID duplicate -> one result
same-ID conflict -> two preserved entries
legacy transaction first claim -> active entitlement
same-account replay -> same entitlement
other-account claim -> blocked
second device -> same entitlement list
```

No response body containing IDs, tokens, diary JSON, hashes, or transaction evidence is written to Git logs.

- [ ] **Step 3: Run staging smoke with migration writes enabled**

```bash
CLOVERY_API_BASE_URL=https://api.staging.clovery.cn \
  SECURE_EVIDENCE_DIR="$HOME/CloveryReleaseEvidence/1.1.0" \
  v2/scripts/smoke-account-inheritance.sh

CLOVERY_API_BASE_URL=https://api.staging.clovery.cn \
  SECURE_EVIDENCE_DIR="$HOME/CloveryReleaseEvidence/1.1.0" \
  v2/scripts/smoke-legacy-entitlement.sh
```

Expected: every named scenario reports PASS.

- [ ] **Step 4: Test transient failure and recovery**

Temporarily block object storage, Apple verification, and database write paths one at a time in staging. Confirm jobs stay pending/needs-attention as designed, local evidence remains, and retry completes after dependency restoration. Do not simulate failure in production.

- [ ] **Step 5: Record staging acceptance**

Record commit/deployment SHA, migration version, test time, aggregate scenario status, and operator. Do not record test account IDs or StoreKit transaction data.

- [ ] **Step 6: Commit smoke tooling and summary**

```bash
git add v2/scripts/smoke-* v2/docs/release/ios-1.1.0-staging-acceptance.md \
  v2/infra/staging/.env.example
git commit -m "test(staging): verify account inheritance"
```

## Task 5: Close All Automated iOS and Backend Gates

**Files:**
- Modify as failures require: `CloveryTests/AuthenticationAPIClientTests.swift`
- Modify as failures require: `CloveryTests/AuthenticationSessionStoreTests.swift`
- Modify as failures require: `CloveryTests/TestSupport/*`
- Modify: `scripts/verify-ios-v1.sh`
- Create: `scripts/verify-ios-1.1.0.sh`
- Create: `docs/superpowers/verification/2026-07-19-w10-automated.md`

- [ ] **Step 1: Run the complete backend gate**

```bash
cd /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/v2/services/api
GOCACHE=/private/tmp/clovery-go-build go test -race ./...
GOCACHE=/private/tmp/clovery-go-build go build ./cmd/api
```

Expected: both commands exit `0`. Investigate race failures; do not disable `-race` for affected packages.

- [ ] **Step 2: Run the complete iOS suite with production URL supplied**

```bash
cd /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation
CLOVERY_RELEASE_API_BASE_URL=https://api.clovery.cn \
  xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination "$(scripts/select-ios-simulator.sh)" \
  -resultBundlePath /private/tmp/Clovery-1.1.0.xcresult test
```

Expected: every XCTest passes. Known fixture-body-stream and simulator Keychain issues must be fixed through deterministic `URLProtocol` body capture and injectable security-store test doubles or a properly signed test host. Do not skip, delete, or weaken the assertions.

- [ ] **Step 3: Run HTML, bridge, photo, StoreKit, privacy, and migration gates**

```bash
node scripts/validate-v1-html.cjs
scripts/test-v1-p0-contract.sh
scripts/test-v1-bridge.sh
scripts/test-migration-zip.sh
Tests/IOSReleaseIdentityTests.sh
Tests/RepositoryHygieneTests.sh
```

Expected: all commands exit `0`.

- [ ] **Step 4: Build unsigned and signed Release variants**

Unsigned simulator:

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/Clovery-1.1.0-Release build CODE_SIGNING_ALLOWED=NO
```

Signed device archive is deferred to Task 8 after true-device testing.

- [ ] **Step 5: Create one verification script**

`scripts/verify-ios-1.1.0.sh` runs all non-device gates in a deterministic order, selects a simulator, writes transient outputs under `/private/tmp` or ignored `build/`, and cleans them after producing the redacted summary.

- [ ] **Step 6: Record and commit automated evidence**

The evidence document lists command, exit code, Xcode/Swift/Go/PostgreSQL versions, simulator runtime, test count, and tested SHA. It contains no raw logs.

```bash
git add scripts/verify-ios-1.1.0.sh scripts/verify-ios-v1.sh \
  CloveryTests docs/superpowers/verification/2026-07-19-w10-automated.md
git commit -m "test(release): close automated iOS gates"
```

## Task 6: Complete Simulator UX and Crash Matrix

**Files:**
- Create: `docs/release/ios-1.1.0-simulator-matrix.md`
- Create: `CloveryUITests/AccountUpgradeUITests.swift`
- Modify: `Clovery.xcodeproj/project.pbxproj`
- Modify: `Clovery.xcodeproj/xcshareddata/xcschemes/Clovery.xcscheme`

- [ ] **Step 1: Add the UI-test target and deterministic launch fixtures**

Create a `CloveryUITests` XCTest UI target with bundle ID `com.clovery.app.UITests`, host application `Clovery`, no production signing entitlement, and membership limited to UI-test sources. Add it to the shared scheme's Test action and CI.

Fixtures exist only in `DEBUG`/UI-test process and cannot compile into behavior selected by production users. Cover routes:

```text
clean auth
mandatory notice
identity claim
reconciling each stage
needs attention
authenticated diary
account security/deletion
```

- [ ] **Step 2: Run screen-size matrix**

At minimum:

```text
iPhone SE (3rd generation), iOS 16 runtime if installed
iPhone 13 mini or smallest available notch device
iPhone 16 Pro
iPhone 16 Pro Max
```

Verify no keyboard collision, clipped provider row, hidden action, unsafe-area overlap, blank screen, or crash.

- [ ] **Step 3: Run accessibility/font matrix**

For every route, verify:

```text
default text size
largest accessibility text size
VoiceOver reading order/labels
Reduce Motion
light and dark system appearance where supported
each user-selectable Clovery font
Simplified Chinese copy
```

The app's own visual theme may remain light, but controls and system sheets must remain readable in dark mode.

- [ ] **Step 4: Verify interruption matrix**

Terminate and relaunch during claim, migration upload, entitlement verification, and vault pull. Toggle network offline/online. Rotate background/foreground. Confirm the same checkpoint resumes and the diary remains gated.

- [ ] **Step 5: Verify P0 photo behavior in simulator tests**

Retain unit/bridge coverage for save, denial/settings recovery, share independence, invalid image, and success callbacks. Simulator cannot replace the physical Photos permission gate in Task 7.

- [ ] **Step 6: Record redacted matrix and commit**

Screenshots go to ignored release evidence; Git records PASS/FAIL by route/device/runtime only.

```bash
git add docs/release/ios-1.1.0-simulator-matrix.md CloveryUITests \
  Clovery.xcodeproj/project.pbxproj Clovery.xcodeproj/xcshareddata/xcschemes/Clovery.xcscheme
git commit -m "test(ios): verify account upgrade UX matrix"
```

## Task 7: Run the Deferred Physical-Device Upgrade Gate

**Files:**
- Create: `docs/release/ios-1.1.0-device-acceptance.md`
- Modify: `docs/release/ios-1.1.0-acceptance.md`

- [ ] **Step 1: Prepare two physical devices after W9 completion**

Required matrix:

```text
Device A: iOS 16-compatible older iPhone with App Store 1.0.3 data
Device B: current supported iPhone with no local Clovery data
```

Do not start this task before all automated and simulator gates pass. Record model and OS only; never commit UDID or Apple ID.

- [ ] **Step 2: Create a controlled 1.0.3 legacy fixture on Device A**

Using the published App Store build, create multiple diaries including:

```text
Chinese/Japanese text
long text
custom tags and ordering
multiple photos
one duplicate-content entry
one edited same-ID conflict fixture through approved debug migration tooling
selected non-default font
```

Take an encrypted local backup before installing 1.1.0. Do not commit its contents.

- [ ] **Step 3: Test true in-place upgrade**

Install signed 1.1.0 over 1.0.3 without uninstalling. Verify:

```text
original loading screen appears
mandatory Chinese notice appears once
我已知晓 leads to authentication
iOS shows CloveryID plus Apple/Google only
Apple verified-unbound flow creates custom CloveryID
same Apple identity becomes a login method, not the account root
migration preserves all diaries/photos/conflicts
font choice applies to notice/auth/reconciliation/diary
no crash during backgrounding or low-memory relaunch
```

- [ ] **Step 4: Verify cross-device Vault inheritance**

On Device B, install 1.1.0 and log in with the same Clovery account using another bound method or CloveryID. Verify identical diary count/content/photo availability, entitlement, and vault ID via redacted operator tooling. New local records sync back to Device A without duplication.

- [ ] **Step 5: Verify Photos P0 on real hardware**

Test first permission, add-only authorization, denial, Settings recovery, repeated save, and share. Confirm saved images appear in Photos at expected resolution and sharing still works independently. Any save failure blocks release.

- [ ] **Step 6: Verify old Apple-bound user path**

Use a controlled legacy account already bound to Apple. Confirm Apple login returns the existing Clovery account/vault and does not open account creation. If no safe fixture exists, create one in staging before production device acceptance.

- [ ] **Step 7: Verify deletion and logout**

With a disposable account, request deletion in app, confirm immediate session revocation, inability to re-enter diary, and backend deletion request status. Do not use the main paid/migration fixture.

- [ ] **Step 8: Record device acceptance**

Git contains only aggregate PASS, device model, OS, build, date, and tester. Restricted screenshots, encrypted backups, and redacted support exports stay under ignored secure evidence.

- [ ] **Step 9: Commit the true-device gate**

```bash
git add docs/release/ios-1.1.0-device-acceptance.md \
  docs/release/ios-1.1.0-acceptance.md
git commit -m "test(ios): accept physical device upgrade"
```

Expected: all physical-device rows are PASS before Task 8.

## Task 8: Verify App Store Connect, Sandbox Purchases, and TestFlight

**Files:**
- Create: `docs/release/ios-1.1.0-storekit-acceptance.md`
- Modify: `docs/release/ios-1.1.0-acceptance.md`
- Modify: `docs/incidents/2026-07-11-v1-photo-iap-p0.md`

- [ ] **Step 1: Audit App Store Connect product configuration**

For `com.clovery.app.board.lifetime`, verify:

```text
type Non-Consumable
belongs to app/bundle com.clovery.app
Paid Applications agreement Active
tax and banking complete
Simplified Chinese display name/description complete
price and mainland China availability set
review screenshot and review notes complete
status has no red action indicator
product is added to the 1.1.0 submission if it is the first review
```

App Store Connect trend value `0` is not proof that a user did not pay; acceptance uses verified StoreKit/App Store Server transaction evidence and server entitlement state.

- [ ] **Step 2: Audit server-side Apple configuration**

Verify production and sandbox App Store Server API credentials, bundle ID, product allowlist, root certificates, clock, and App Store Server Notifications V2 URLs. Trigger Apple's test notification and confirm idempotent processing without logging signed payloads.

- [ ] **Step 3: Run development-signed Sandbox purchase on Device A**

Use a Sandbox Apple Account and real App Store Connect product data, not only `Clovery.storekit`. Verify displayed price, cancel, pending/interrupted purchase, success, backend account token, entitlement unlock, relaunch, restore, refund/revocation simulation, and second-device restore.

- [ ] **Step 4: Verify the affected-user remediation path**

For the reported paid user, do not request passwords or full JWS over chat. After the user authenticates a Clovery account, use the in-app restore/legacy claim flow. Support may collect only a short support code and Apple-provided transaction lookup result through secure tooling. Confirm the entitlement appears in `/v1/account/entitlements`; never manually flip a local paid flag.

- [ ] **Step 5: Create signed archive**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Clovery-1.1.0-15.xcarchive archive
```

Inspect archive:

```bash
xcodebuild -archivePath build/Clovery-1.1.0-15.xcarchive -showBuildSettings
codesign -d --entitlements :- build/Clovery-1.1.0-15.xcarchive/Products/Applications/Clovery.app
```

Expected: bundle/version/team/capabilities match the release identity. Archive remains ignored and is not committed.

- [ ] **Step 6: Validate and upload with Xcode Organizer**

Use Organizer `Validate App`, then `Distribute App -> App Store Connect -> Upload`. Confirm symbols upload, privacy manifest validation, no StoreKit local configuration in Release, and build `1.1.0 (15)` appears in App Store Connect.

- [ ] **Step 7: Run TestFlight matrix**

TestFlight uses Sandbox purchases. Run on both physical devices:

```text
clean install account creation
1.0.3 App Store -> 1.1.0 TestFlight upgrade
Apple claim and bound login
legacy diary/photo migration
existing paid-user claim
new purchase with appAccountToken
relaunch/reinstall restore
second-device same-account restore
photo save/share
account deletion
```

- [ ] **Step 8: Update privacy and review metadata**

In App Store Connect:

- set privacy policy URL to `https://api.clovery.cn/v1/legal/privacy`;
- update privacy answers for account identifier, user content, photos only when uploaded by user, purchase history, diagnostics, and linked/unlinked usage exactly as implemented;
- provide reviewer account and review notes explaining mandatory legacy notice, test CloveryID, Apple login, migration, purchase restore, and account deletion;
- do not place production credentials or real user data in review notes.

- [ ] **Step 9: Record StoreKit/TestFlight acceptance**

All scenarios must be PASS. Evidence contains environment and product ID but no account email, Apple ID, transaction ID, JWS, receipt, or account UUID.

- [ ] **Step 10: Commit release evidence**

```bash
git add docs/release/ios-1.1.0-storekit-acceptance.md \
  docs/release/ios-1.1.0-acceptance.md \
  docs/incidents/2026-07-11-v1-photo-iap-p0.md
git commit -m "test(storekit): accept account entitlements"
```

## Task 9: Deploy, Phase Release, Monitor, and Publish GitHub Release

**Files:**
- Create: `docs/release/ios-1.1.0-production-checklist.md`
- Create: `docs/release/ios-1.1.0-monitoring.md`
- Modify: `docs/release/ios-1.1.0-acceptance.md`

- [ ] **Step 1: Merge through a reviewed pull request**

Ensure branch is current with the protected release branch, CI is green, W7-W10 evidence is complete, and no secrets/build output are staged. Create a non-draft PR from `codex/swift-auth-foundation`, obtain review, and merge without rewriting published history.

- [ ] **Step 2: Take final production database backup**

Run the approved backup script, verify restore metadata, deploy additive migrations `000016` and `000017`, run verification, then deploy the W7-W8 API. Keep migration writes disabled until health/smoke checks pass.

- [ ] **Step 3: Run production-safe canary smoke**

Use dedicated operator test accounts and sandbox billing only. Verify auth, bootstrap status, empty migration, and entitlement listing. Do not upload synthetic diaries into real user vaults.

- [ ] **Step 4: Enable migration writes and monitor backend**

Monitor:

```text
identity claim issue/consume/replay rates
claim registration transaction failures
bootstrap pending/needs-attention duration
migration integrity/resolution counts
Apple verification unavailable/cross-account claim
entitlement active/revoked transitions
5xx, latency, database locks, object storage failures
```

Metrics and logs use aggregate counts and short support IDs only.

- [ ] **Step 5: Submit App Store version and use phased release**

Submit `1.1.0 (15)` with the non-consumable product as required. After approval, start phased release. Do not manually release to 100% until the first cohort shows no P0 and bootstrap completion rate is healthy.

- [ ] **Step 6: Execute rollback if a P0 occurs**

```text
pause App Store phased release
disable migration writes
preserve all local/server staging data
deploy previous compatible API binary if backend-caused
do not down-migrate production DB first
publish in-app/status communication
open incident with affected support IDs
prepare fixed build with incremented build number
```

Never delete incomplete migrations or revoke user entitlements as a rollback shortcut.

- [ ] **Step 7: Tag and publish GitHub release after production acceptance**

```bash
git tag -a ios-v1.1.0 -m "Clovery iOS 1.1.0"
git push origin ios-v1.1.0
gh release create ios-v1.1.0 \
  --title "Clovery iOS 1.1.0" \
  --notes-file docs/release/1.1.0-ios-release.md
```

Do not attach `.ipa`, `.xcarchive`, database dump, JWS, receipts, screenshots containing user content, or signing material to the public release.

- [ ] **Step 8: Clean local generated artifacts after evidence extraction**

Remove only ignored, reproducible build outputs such as `build/DerivedData-*`, `/private/tmp/Clovery-*`, XCResult, and local archives after confirming GitHub source and redacted evidence are pushed. Keep source, migrations, legal docs, tests, runbooks, and user-controlled legacy backups on test devices.

- [ ] **Step 9: Record final acceptance and unlock Flutter**

Mark W10 complete only after:

```text
production backend healthy
App Store 1.1.0 available to intended cohort
no open P0/P1
paid-user remediation verified
GitHub tag/release published
physical-device gate PASS
```

Then update the rebuild program to allow Flutter W3. Commit and push final documentation:

```bash
git add docs/release docs/superpowers/plans/2026-07-10-clovery-rebuild-program.md
git commit -m "docs(release): complete iOS 1.1.0 rollout"
git push origin main
```

## W10 Non-Goals

- Do not replace the iOS diary WebView with Flutter.
- Do not publish Android or HarmonyOS packages.
- Do not migrate two existing Clovery root accounts automatically.
- Do not use App Store analytics alone to decide an individual purchase claim.
- Do not store production secrets, transaction proofs, user content, or database backups in GitHub.
- Do not delete legacy user data after a successful account migration.
- Do not call iOS “complete” before physical-device and TestFlight inheritance gates pass.
