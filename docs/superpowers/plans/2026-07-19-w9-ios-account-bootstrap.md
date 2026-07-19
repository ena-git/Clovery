# W9 Native iOS Account Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the native Swift iOS upgrade flow so old and new users authenticate into a Clovery root account, safely inherit local/CloudKit data and Apple purchases, pull the account vault, and enter the existing diary only after reconciliation is complete.

**Architecture:** Replace route decisions scattered across views with one `AccountBootstrapCoordinator` state machine. Keep authentication, identity claims, legacy snapshot collection, migration transport, StoreKit reconciliation, vault pull, and presentation in separate modules. The existing WebView diary remains the iOS homepage for this release, but it receives account-vault data only after the server bootstrap reaches complete. All new native UI uses the existing Figma-derived colors, shapes, spacing, Chinese copy, and global Clovery font environment.

**Tech Stack:** Swift 5, SwiftUI, Combine, async/await, URLSession, WKWebView, StoreKit 2, CryptoKit, Keychain, XCTest, Xcode iOS Simulator, existing Go/OpenAPI contracts from W7 and W8.

---

## Scope, Dependencies, and User-Visible Contract

W9 depends on accepted W7 and W8 API contracts. It does not begin Flutter, Android, or HarmonyOS UI work. Physical-device testing remains deferred to W10, after native iOS completion and before Flutter begins.

### Required launch routes

```text
loading
├── legacy data + notice not acknowledged -> upgradeNotice
├── no valid Clovery session             -> authentication
└── valid Clovery session                -> reconciling

upgradeNotice --我已知晓--> authentication

authentication
├── CloveryID login/register             -> reconciling
├── bound Apple/Google login              -> reconciling
└── verified unbound Apple/Google         -> identityClaimRegistration

identityClaimRegistration
└── custom CloveryID + password           -> reconciling

reconciling
└── migration + entitlement + vault pull complete -> diary
```

There is no route from the notice or authentication flow directly to the diary.

### iOS provider contract

- CloveryID/password remains the default form and primary action.
- Show Apple and Google quick-login buttons only when their runtime configuration is usable.
- Hide Huawei and Passkey from first-screen login and registration rows on iOS.
- Keep Passkey code for account security/recovery, not the first screen.
- A verified unbound provider opens CloveryID creation; it does not show the old “先登录已有账户后绑定” dead end.

### Data ownership contract

- The first authenticated Clovery account selected for migration owns the migration checkpoint.
- A different account cannot silently upload the same device's old data while the first migration is running or complete.
- Local backups, WebKit local storage, CloudKit data, photo files, and migration archives are never automatically deleted.
- `BoardStore.isUnlocked` is derived from the authenticated account's server entitlement, not a permanent local boolean.

## New iOS Module Map

```text
Clovery/
├── Application/
│   ├── Bootstrap/
│   │   ├── AccountBootstrapCoordinator.swift
│   │   ├── BootstrapRoute.swift
│   │   ├── BootstrapDependencies.swift
│   │   └── BootstrapCheckpointStore.swift
│   ├── ApplicationLoadingView.swift
│   ├── ApplicationRootView.swift
│   └── ApplicationSessionController.swift
├── Core/
│   ├── Networking/AuthenticatedAPIClient.swift
│   └── Storage/AtomicJSONFileStore.swift
├── Features/
│   ├── Authentication/
│   │   ├── Data/IdentityClaimAPI.swift
│   │   ├── Domain/ProviderVisibilityPolicy.swift
│   │   └── Presentation/
│   │       ├── IdentityClaimRegistrationView.swift
│   │       └── IdentityClaimRegistrationViewModel.swift
│   ├── Bootstrap/
│   │   ├── Data/AccountBootstrapAPI.swift
│   │   └── Presentation/AccountReconciliationView.swift
│   ├── Entitlements/
│   │   ├── Data/AccountEntitlementAPI.swift
│   │   ├── Data/AccountEntitlementCache.swift
│   │   └── Domain/EntitlementReconciler.swift
│   ├── Migration/
│   │   ├── Data/LegacyMigrationAPI.swift
│   │   ├── Data/LegacySnapshotReader.swift
│   │   ├── Data/LegacySnapshotSources.swift
│   │   ├── Domain/LegacySnapshotMerger.swift
│   │   ├── Domain/LegacyMigrationCoordinator.swift
│   │   └── Domain/LegacyMigrationCheckpointStore.swift
│   ├── Sync/
│   │   ├── Data/VaultSyncAPI.swift
│   │   ├── Data/VaultAssetAPI.swift
│   │   ├── Domain/InitialVaultPuller.swift
│   │   ├── Domain/VaultAssetUploader.swift
│   │   ├── Domain/VaultSyncCheckpointStore.swift
│   │   └── Domain/VaultSyncCoordinator.swift
│   └── Upgrade/
│       ├── LegacyDataDetector.swift
│       └── UpgradeNoticeView.swift
└── MigrationBundle.swift
```

No source file introduced by W9 should exceed roughly 300 lines without a documented reason. Split request models, persistence, orchestration, and UI rather than collecting them in `ApplicationRootView`, `AuthenticationAPI`, or `WebView`.

The `CloveryTests` group is filesystem-synchronized. Every new application source must be explicitly added to the `Clovery` group and `PBXSourcesBuildPhase` in `Clovery.xcodeproj/project.pbxproj`.

## Task 1: Add Typed Federated Claim and Authenticated API Transport

**Files:**
- Modify: `Clovery/Core/Networking/APIClient.swift`
- Create: `Clovery/Core/Networking/AuthenticatedAPIClient.swift`
- Modify: `Clovery/Features/Authentication/Data/AuthenticationModels.swift`
- Modify: `Clovery/Features/Authentication/Data/AuthenticationAPI.swift`
- Create: `Clovery/Features/Authentication/Data/IdentityClaimAPI.swift`
- Modify: `Clovery/Application/ApplicationSessionController.swift`
- Modify: `CloveryTests/AuthenticationAPIClientTests.swift`
- Create: `CloveryTests/AuthenticatedAPIClientTests.swift`
- Create: `CloveryTests/IdentityClaimAPITests.swift`
- Modify: `CloveryTests/TestSupport/AuthenticationAPISpy.swift`

- [ ] **Step 1: Write federated union decoding tests**

Require decoding of both W7 responses:

```swift
enum FederatedLoginCompletion: Equatable {
    case authenticated(AuthSessionResponse)
    case identityClaim(IdentityClaimContext)
}

struct IdentityClaimContext: Codable, Equatable, Hashable {
    let provider: IdentityProvider
    let token: String
    let expiresAt: Date
}
```

Tests must prove:

```text
HTTP 200 session -> .authenticated
HTTP 202 identity_claim_required -> .identityClaim
claim response with account or vault fields -> decoding failure
session response without account/vault -> decoding failure
claim token never appears in APIError.localizedDescription
```

- [ ] **Step 2: Write access-token refresh tests**

`AuthenticatedAPIClient` must:

- attach the current bearer token;
- refresh once when expiry is within 60 seconds;
- coalesce concurrent refresh calls;
- save the rotated refresh token through `ApplicationSessionController`;
- log out only on terminal refresh rejection, not transient transport errors;
- never log access or refresh tokens.

- [ ] **Step 3: Run focused tests and observe failures**

```bash
cd /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/AuthenticationAPIClientTests \
  -only-testing:CloveryTests/AuthenticatedAPIClientTests \
  -only-testing:CloveryTests/IdentityClaimAPITests test
```

Expected: new tests fail to compile or old API expects only `AuthSessionResponse`.

- [ ] **Step 4: Add status-preserving API responses**

Refactor `APIClient` so its private request execution returns status and data:

```swift
struct APIResponse<Value> {
    let statusCode: Int
    let value: Value
}

func sendResponse<Response: Decodable>(
    _ request: APIRequest,
    decoding: Response.Type
) async throws -> APIResponse<Response>
```

Keep the existing `send` method as a compatibility wrapper returning only `.value`.

- [ ] **Step 5: Change the federation protocol to the union**

`completeFederatedLogin` returns `FederatedLoginCompletion`. Decode by HTTP status and `status`, not by catching `identity_not_bound`. Remove `.requiresExistingAccountBinding` from `FederatedLoginOutcome`; add `.identityClaim(IdentityClaimContext)`.

- [ ] **Step 6: Add claim-aware registration**

Keep plain registration in `AuthenticationAPI`. Put claim registration in `IdentityClaimAPI`:

```swift
protocol IdentityClaimAPIProtocol {
    func register(
        loginID: String,
        password: String,
        claim: IdentityClaimContext,
        registrationRequestID: UUID,
        sourceKind: BootstrapSourceKind,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse
}
```

Send `recovery_method: bound_identity`. Generate `registrationRequestID` in the view model once and reuse it for every retry. Never persist the claim token to UserDefaults or Keychain.

- [ ] **Step 7: Implement authenticated transport**

Use an actor for refresh coalescing and a narrow session-controller protocol. `AuthenticatedAPIClient.send` asks for a valid token, copies the request with `bearerToken`, and retries exactly once after a `401` caused by token expiry. It never retries non-idempotent requests unless the caller supplies its stable request/migration ID.

- [ ] **Step 8: Run focused tests**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/AuthenticationAPIClientTests \
  -only-testing:CloveryTests/AuthenticatedAPIClientTests \
  -only-testing:CloveryTests/IdentityClaimAPITests test
```

Expected: selected tests pass.

- [ ] **Step 9: Register new sources and commit**

Add the new Swift files to `Clovery.xcodeproj/project.pbxproj`, then:

```bash
git add Clovery/Core/Networking Clovery/Features/Authentication \
  Clovery/Application/ApplicationSessionController.swift \
  CloveryTests Clovery.xcodeproj/project.pbxproj
git commit -m "feat(ios): support federated identity claims"
```

## Task 2: Enforce Device-Aware Provider Visibility

**Files:**
- Create: `Clovery/Features/Authentication/Domain/ProviderVisibilityPolicy.swift`
- Modify: `Clovery/Features/Authentication/Presentation/Components/AuthProviderButton.swift`
- Modify: `Clovery/Features/Authentication/Presentation/LoginView.swift`
- Modify: `Clovery/Features/Authentication/Presentation/SignUpView.swift`
- Modify: `Clovery/Features/Authentication/Presentation/AuthenticationFlowView.swift`
- Modify: `Clovery/Features/Authentication/Presentation/AuthenticationProviderViewModel.swift`
- Modify: `Clovery/Features/Authentication/Providers/ProviderAuthentication.swift`
- Create: `CloveryTests/ProviderVisibilityPolicyTests.swift`
- Modify: `CloveryTests/ProviderAuthenticationTests.swift`

- [ ] **Step 1: Write the full cross-platform policy matrix test**

Even though W9 ships only iOS UI, encode the agreed shared contract:

```swift
enum ClientPlatform {
    case iOS
    case huaweiHarmony
    case androidOther
}

XCTAssertEqual(policy.quickProviders(for: .iOS), [.apple, .google])
XCTAssertEqual(policy.quickProviders(for: .huaweiHarmony), [.huawei])
XCTAssertEqual(policy.quickProviders(for: .androidOther), [.google])
```

Also assert `.passkey` is absent from every first-screen list and CloveryID remains the default method.

- [ ] **Step 2: Run focused tests and observe failure**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/ProviderVisibilityPolicyTests \
  -only-testing:CloveryTests/ProviderAuthenticationTests test
```

Expected: policy does not exist and provider outcome still uses the old binding case.

- [ ] **Step 3: Implement pure policy plus runtime availability**

The visible list is:

```swift
policy.quickProviders(for: .iOS)
    .filter(providerViewModel.isAvailable)
```

Hide unavailable buttons instead of showing disabled placeholders. Keep provider icon sizes, spacing, dashed divider, background, and Figma typography unchanged.

Remove `.wechat` and `.qq` from `IdentityProvider` because they are not part of the approved or implemented federation contract. CloveryID remains password authentication and is not represented as an external identity provider.

- [ ] **Step 4: Route unbound providers to claim registration**

`AuthenticationProviderViewModel` publishes a one-shot `identityClaim` event. `AuthenticationFlowView` appends `.identityClaim(context)` and clears the event after navigation. Successful bound login still accepts the session and exits auth.

- [ ] **Step 5: Run provider tests**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/ProviderVisibilityPolicyTests \
  -only-testing:CloveryTests/ProviderAuthenticationTests test
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit provider policy**

```bash
git add Clovery/Features/Authentication CloveryTests/ProviderVisibilityPolicyTests.swift \
  CloveryTests/ProviderAuthenticationTests.swift Clovery.xcodeproj/project.pbxproj
git commit -m "feat(ios): adapt quick login providers"
```

## Task 3: Add CloveryID Creation After Provider Verification

**Files:**
- Create: `Clovery/Features/Authentication/Presentation/IdentityClaimRegistrationView.swift`
- Create: `Clovery/Features/Authentication/Presentation/IdentityClaimRegistrationViewModel.swift`
- Modify: `Clovery/Features/Authentication/Presentation/AuthenticationFlowView.swift`
- Modify: `Clovery/Features/Authentication/Domain/AuthenticationValidation.swift`
- Create: `CloveryTests/IdentityClaimRegistrationViewModelTests.swift`
- Modify: `CloveryTests/AuthenticationRoutingTests.swift`

- [ ] **Step 1: Write view-model behavior tests**

Require:

```text
custom CloveryID uses existing 4..24 validation
password accepts 8 and rejects 7 characters
password confirmation must match
registration request UUID remains stable across retry
claim expiry blocks submit and requests provider authorization again
login_id_unavailable preserves valid claim and user input
success accepts exactly the returned account/vault session
claim token is cleared from memory when flow exits
```

- [ ] **Step 2: Run focused tests and observe missing types**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/IdentityClaimRegistrationViewModelTests \
  -only-testing:CloveryTests/AuthenticationRoutingTests test
```

Expected: failure because claim registration UI is absent.

- [ ] **Step 3: Implement the modular view model**

The view model owns fields, validation, one registration request UUID, loading state, and safe Chinese error copy. It delegates API, device registration, and session acceptance through injected protocols. It must not own navigation or bootstrap orchestration.

- [ ] **Step 4: Reuse the existing Figma visual language**

Build the view from existing:

```text
AuthDashedCard
AuthTextField
AuthDivider
AuthenticationTheme colors
.cloveryFont(...)
```

Use Chinese copy:

```text
创建 Clovery 账户
已验证 Apple 登录，请设置你的 Clovery ID
Clovery ID...
密码…
确认密码…
创建并继续
```

Provider name is dynamic. Do not show the claim token, Apple email, or subject. Keep all typography responsive to `AppFontStore` through the environment.

- [ ] **Step 5: Integrate navigation**

Add `AuthenticationRoute.identityClaim(IdentityClaimContext)`. On success, `ApplicationSessionController` changes to authenticated and the root bootstrap coordinator takes over. On expiry, pop to the previous auth screen with “登录验证已过期，请重新授权”.

- [ ] **Step 6: Run selected tests and a build**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/IdentityClaimRegistrationViewModelTests \
  -only-testing:CloveryTests/AuthenticationRoutingTests test
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: tests and simulator build pass.

- [ ] **Step 7: Commit claim registration UI**

```bash
git add Clovery/Features/Authentication CloveryTests \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat(ios): create CloveryID from identity claim"
```

## Task 4: Replace Legacy Routing with One Bootstrap State Machine

**Files:**
- Create: `Clovery/Application/Bootstrap/BootstrapRoute.swift`
- Create: `Clovery/Application/Bootstrap/BootstrapDependencies.swift`
- Create: `Clovery/Application/Bootstrap/BootstrapCheckpointStore.swift`
- Create: `Clovery/Application/Bootstrap/AccountBootstrapCoordinator.swift`
- Create: `Clovery/Application/ApplicationLoadingView.swift`
- Create: `Clovery/Features/Bootstrap/Data/AccountBootstrapAPI.swift`
- Modify: `Clovery/Application/LegacyUpgradeController.swift`
- Modify: `Clovery/Features/Upgrade/UpgradeNoticeView.swift`
- Modify: `Clovery/Application/ApplicationRootView.swift`
- Modify: `CloveryTests/LegacyUpgradeControllerTests.swift`
- Create: `CloveryTests/AccountBootstrapCoordinatorTests.swift`
- Create: `CloveryTests/AccountBootstrapAPITests.swift`

- [ ] **Step 1: Write pure route transition tests**

Cover the complete matrix:

```text
legacy + unacknowledged notice -> upgradeNotice before session restoration route
acknowledge notice -> authentication when no session
new install + no session -> authentication
valid session -> reconciling, never diary
auth success -> reconciling
claim registration success -> reconciling
reconciliation complete -> diary
any pending stage -> reconciling
needs_attention -> reconciling with retry/support state
logout -> authentication without clearing legacy data
app restart resumes stored bootstrap job
```

- [ ] **Step 2: Update the old routing test to fail safely**

Replace `testLegacyInstallationWithoutSessionStillStartsDiary` with an assertion that legacy users cannot reach diary before authentication. Keep the existing assertion that notice acknowledgement does not delete data.

- [ ] **Step 3: Run focused tests and observe old direct-diary behavior**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/LegacyUpgradeControllerTests \
  -only-testing:CloveryTests/AccountBootstrapCoordinatorTests \
  -only-testing:CloveryTests/AccountBootstrapAPITests test
```

Expected: old route returns `.legacyDiaryWithUpgradeNotice` or `.diary`.

- [ ] **Step 4: Keep notice persistence separate from routing**

Reduce `LegacyUpgradeController` to notice detection/acknowledgement or rename its role internally without deleting compatibility keys. The bootstrap coordinator owns routes. Persist an explicit notice schema version, not only the marketing version, so a hotfix does not unnecessarily repeat the same announcement.

- [ ] **Step 5: Make the notice mandatory and Chinese**

`UpgradeNoticeView` has one action:

```text
欢迎升级 Clovery
为了安全地保存并同步你的日记、照片和已购权益，本次更新需要创建或登录 Clovery 账户。你的现有内容仍保留在设备中，完成绑定前不会删除或覆盖。
我已知晓
```

Remove “稍后” and the old optional sheet. Apply `.cloveryFont` to all text and button labels. Disable interactive dismissal because the notice is a route, not a sheet.

Render the notice over `ApplicationLoadingView`, which reproduces the existing V1 splash/background rather than exposing the diary underneath. The loading view is noninteractive, hidden from VoiceOver behind the notice, and never initializes diary data access before authentication.

- [ ] **Step 6: Implement `AccountBootstrapAPI`**

Typed methods:

```swift
func status() async throws -> AccountBootstrapStatus
func resume(sourceKind: BootstrapSourceKind, vaultCheckpoint: VaultCheckpoint?) async throws -> AccountBootstrapStatus
```

Use authenticated transport. Decode all four stage states and stable error codes. Unknown enum values become a safe `.needsAttention("bootstrap_contract_unknown")`, never `.complete`.

- [ ] **Step 7: Implement coordinator lifecycle**

The coordinator is `@MainActor`, publishes one `BootstrapRoute`, and delegates work to protocols. It cancels previous tasks on logout/account change, ignores stale completions using an account/vault generation token, and never stores refresh or claim tokens in checkpoints.

- [ ] **Step 8: Integrate root view without a large switch body**

Move dependency creation into `BootstrapDependencies`. `ApplicationRootView` renders small route views and no longer decides legacy/session combinations itself. The diary is rendered only for `.diary(accountID:vaultID:)` after coordinator completion.

- [ ] **Step 9: Run routing tests and build**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/LegacyUpgradeControllerTests \
  -only-testing:CloveryTests/AccountBootstrapCoordinatorTests \
  -only-testing:CloveryTests/AccountBootstrapAPITests test
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: selected tests and build pass.

- [ ] **Step 10: Commit the state machine**

```bash
git add Clovery/Application Clovery/Features/Bootstrap Clovery/Features/Upgrade \
  CloveryTests Clovery.xcodeproj/project.pbxproj
git commit -m "feat(ios): gate launch on account bootstrap"
```

## Task 5: Collect Every Legacy Source Without Destructive Merge

**Files:**
- Create: `Clovery/Features/Migration/Data/LegacySnapshotReader.swift`
- Create: `Clovery/Features/Migration/Data/LegacySnapshotSources.swift`
- Create: `Clovery/Features/Migration/Domain/LegacySnapshotMerger.swift`
- Modify: `Clovery/Features/Upgrade/LegacyDataDetector.swift`
- Modify: `Clovery/WebView.swift`
- Modify: `Clovery/MigrationBundle.swift`
- Modify: `Clovery/MigrationBundleExporter.swift`
- Create: `CloveryTests/LegacySnapshotReaderTests.swift`
- Create: `CloveryTests/LegacySnapshotMergerTests.swift`
- Modify: `CloveryTests/MigrationBundleExporterTests.swift`
- Modify: `CloveryTests/WebBridgeContractTests.swift`

- [ ] **Step 1: Write source and merge tests first**

Provide deterministic fixtures for:

```text
WKWebView localStorage clovery_entries and clovery_deleted_ids
clovery_full_backup.json
clovery_backup.json
NSUbiquitousKeyValueStore compressed and uncompressed entries
CloudKit records and downloaded photo files
UserDefaults legacy markers
```

Require merge behavior:

```text
same source ID + same canonical JSON -> one
different source ID + same canonical JSON after removing only identity keys -> one
same source ID + different JSON -> preserve both with stable synthetic source ID
uncertain/invalid source -> preserve valid sources and report warning
full backup photo arrays are never replaced by slim cloud copies
deleted IDs never remove an active conflicting record during collection
```

- [ ] **Step 2: Run focused tests and observe missing collector**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/LegacySnapshotReaderTests \
  -only-testing:CloveryTests/LegacySnapshotMergerTests \
  -only-testing:CloveryTests/MigrationBundleExporterTests \
  -only-testing:CloveryTests/WebBridgeContractTests test
```

Expected: new source/merger tests fail.

- [ ] **Step 3: Extract legacy source loading from `WebView`**

Move backup/KVS decompression and merge helpers out of `WebView.Coordinator`. Keep `WebView` as a consumer. `LegacySnapshotReader` loads the app's existing HTML in an offscreen `WKWebView` using the default website data store, waits for navigation completion, and evaluates only:

```javascript
JSON.stringify({
  entries: localStorage.getItem('clovery_entries') || '[]',
  deletedIDs: localStorage.getItem('clovery_deleted_ids') || '[]'
})
```

Do not log returned JavaScript or diary JSON.

- [ ] **Step 4: Pull CloudKit before freezing the snapshot**

Wrap `CloudKitSync.pullAll` behind an async protocol. Download records/photos into the existing documents photos directory, merge them with local/KVS/backup snapshots, then freeze one immutable snapshot for export. A CloudKit network failure preserves local data and reports a retryable bootstrap error; it must not substitute an empty snapshot and mark migration complete.

- [ ] **Step 5: Preserve source-ID content conflicts locally**

The manifest currently requires unique entry IDs. When two sources contain the same ID with different canonical content, keep the canonical winner's ID and assign the other a stable synthetic ID:

```text
<original-id>:conflict:<first-12-hex-of-sha256>
```

Update that copy's payload `id` to the synthetic ID and add a private `clovery_legacy_source_id` field. This preserves both diaries without depending on collection order. Do not expose the field in UI.

For duplicate comparison, remove only `id` and `clovery_legacy_source_id` before canonicalization. Keep dates, text, tags, photos, ordering, language, and all other user fields so superficially similar but distinct diary records are not collapsed.

- [ ] **Step 6: Let the exporter reuse a checkpoint migration ID**

Change:

```swift
func export(
    migrationID: UUID,
    entriesJSON: String,
    deletedIDsJSON: String,
    sources: [String]
) throws -> MigrationBundleExportResult
```

The coordinator creates and persists the UUID before export. Retrying uses the same archive directory and validates existing content before reuse. A content mismatch creates a needs-attention error instead of overwriting the prior archive.

- [ ] **Step 7: Run source, export, and bridge tests**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/LegacySnapshotReaderTests \
  -only-testing:CloveryTests/LegacySnapshotMergerTests \
  -only-testing:CloveryTests/MigrationBundleExporterTests \
  -only-testing:CloveryTests/WebBridgeContractTests test
```

Expected: all selected tests pass and previous export archives remain present.

- [ ] **Step 8: Commit snapshot collection**

```bash
git add Clovery/Features/Migration Clovery/Features/Upgrade \
  Clovery/WebView.swift Clovery/MigrationBundle* CloveryTests \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat(ios): collect legacy data without loss"
```

## Task 6: Upload and Verify Legacy Migration Idempotently

**Files:**
- Create: `Clovery/Features/Migration/Data/LegacyMigrationAPI.swift`
- Create: `Clovery/Features/Migration/Domain/LegacyMigrationCheckpointStore.swift`
- Create: `Clovery/Features/Migration/Domain/LegacyMigrationCoordinator.swift`
- Create: `Clovery/Core/Storage/AtomicJSONFileStore.swift`
- Create: `CloveryTests/LegacyMigrationAPITests.swift`
- Create: `CloveryTests/LegacyMigrationCheckpointStoreTests.swift`
- Create: `CloveryTests/LegacyMigrationCoordinatorTests.swift`

- [ ] **Step 1: Write exact HTTP contract tests**

Assert this order and payload:

```text
POST /v1/vault/migrations
POST /v1/vault/migrations/{id}/entries for every active and deleted entry
POST /v1/vault/migrations/{id}/assets for every photo
PUT each returned presigned upload_url with required headers
POST /v1/vault/assets/{assetId}/complete
POST /v1/vault/migrations/{id}/verify
GET  /v1/vault/migrations/{id}/report on restart
```

Use the archive's exact manifest bytes as base64 and SHA. Active entry requests contain canonical payload and SHA. Deleted entries contain `{}`, deletion time from snapshot when available, and the empty-object SHA.

- [ ] **Step 2: Write checkpoint state tests**

Checkpoint fields:

```swift
struct LegacyMigrationCheckpoint: Codable, Equatable {
    let accountID: String
    let vaultID: String
    let migrationID: UUID
    let archivePath: String
    var uploadedEntryIDs: Set<String>
    var uploadedPhotoNames: Set<String>
    var verifiedAt: Date?
}
```

Prove atomic save, crash recovery, same-account reuse, and cross-account rejection. Store the file under `Documents/CloveryMigration/checkpoint.json`; do not use UserDefaults for large sets.

- [ ] **Step 3: Write coordinator interruption tests**

Interrupt after each network step and assert retry resumes the same migration ID without re-exporting or deleting data. Also test:

```text
server already has an entry -> continue
server already has an asset -> continue
presigned upload required -> upload then complete
asset status complete -> skip binary upload
verify returns duplicate counts -> success
verify needs_attention -> retain bundle and checkpoint
account/vault changed -> block upload and surface support path
```

- [ ] **Step 4: Run focused tests and observe missing implementation**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/LegacyMigrationAPITests \
  -only-testing:CloveryTests/LegacyMigrationCheckpointStoreTests \
  -only-testing:CloveryTests/LegacyMigrationCoordinatorTests test
```

Expected: new tests fail to compile.

- [ ] **Step 5: Implement typed migration transport**

Keep API models in `LegacyMigrationAPI.swift`, checkpoint persistence in its own file, and orchestration in `LegacyMigrationCoordinator.swift`. Presigned uploads use a separate `URLSession` request and copy only server-required headers. Never attach the Clovery bearer token to object-storage URLs.

- [ ] **Step 6: Implement retry-safe orchestration**

Before first upload, bind the checkpoint to current account/vault. After each accepted entry/photo, atomically persist progress. Mark local checkpoint verified only after the server report is `verified` and all expected counts match. Never remove:

```text
clovery_full_backup.json
clovery_backup.json
Documents/photos
WebKit localStorage
NSUbiquitousKeyValueStore
CloudKit records
migration_bundle.zip
```

- [ ] **Step 7: Run migration tests**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/LegacyMigrationAPITests \
  -only-testing:CloveryTests/LegacyMigrationCheckpointStoreTests \
  -only-testing:CloveryTests/LegacyMigrationCoordinatorTests test
```

Expected: selected tests pass.

- [ ] **Step 8: Commit migration upload**

```bash
git add Clovery/Features/Migration Clovery/Core/Storage CloveryTests \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat(ios): upload legacy vault migration"
```

## Task 7: Reconcile StoreKit with Clovery Account Entitlements

**Files:**
- Create: `Clovery/Features/Entitlements/Data/AccountEntitlementAPI.swift`
- Create: `Clovery/Features/Entitlements/Data/AccountEntitlementCache.swift`
- Create: `Clovery/Features/Entitlements/Domain/EntitlementReconciler.swift`
- Modify: `Clovery/BoardStoreClient.swift`
- Modify: `Clovery/BoardStore.swift`
- Modify: `Clovery/WebView.swift`
- Create: `CloveryTests/AccountEntitlementAPITests.swift`
- Create: `CloveryTests/AccountEntitlementCacheTests.swift`
- Create: `CloveryTests/EntitlementReconcilerTests.swift`
- Modify: `CloveryTests/BoardStoreTests.swift`

- [ ] **Step 1: Write server-entitlement API tests**

Cover:

```text
POST /v1/billing/apple/legacy-claims with signed_transaction_info + environment
POST /v1/billing/apple/transactions/verify with transaction_id + environment
POST /v1/billing/apple/restore with all transaction IDs grouped by environment
GET  /v1/account/entitlements
apple_transaction_claimed -> needs attention
apple_verification_unavailable -> retryable pending
```

No request sends Apple Sign in subject or email.

- [ ] **Step 2: Expand StoreKit transaction evidence tests**

`BoardTransaction` must carry:

```swift
let transactionID: UInt64
let productID: String
let environment: AccountEntitlementEnvironment
let signedTransactionInfo: String
let revocationDate: Date?
```

The live client obtains JWS from `VerificationResult.jwsRepresentation`. Unverified transactions never reach the backend. Tests must prove JWS and transaction IDs are never printed.

- [ ] **Step 3: Require `appAccountToken` for new purchases**

Change purchase to accept the authenticated Clovery account UUID and call:

```swift
product.purchase(options: [.appAccountToken(accountUUID)])
```

If account ID is not a UUID or there is no authenticated account, fail before presenting StoreKit. After verified purchase, call the backend verify endpoint and reload account entitlements before setting `isUnlocked` or finishing the transaction.

- [ ] **Step 4: Write reconciliation behavior tests**

Require:

```text
old verified transaction without appAccountToken -> legacy claim
new transaction with matching account token -> verify
all current transaction IDs -> final restore call
empty StoreKit inventory -> empty restore call
same transaction retry -> idempotent success
cross-account claim -> no unlock, needs attention
server active entitlement -> unlock
local StoreKit active but server rejects -> no permanent unlock
server revoked/expired entitlement -> lock
network failure -> use only recent same-account cache, keep bootstrap pending
```

- [ ] **Step 5: Implement an account-scoped entitlement cache**

Persist only server-returned entitlement summaries, account ID, fetched time, and API environment in Keychain or protected atomic storage with `NSFileProtectionCompleteUntilFirstUserAuthentication`. Never cache signed StoreKit JWS. A cache is usable for at most 72 hours and only for the same authenticated account; stale cache cannot complete bootstrap.

- [ ] **Step 6: Make `BoardStore` server authoritative**

Keep display price, StoreKit purchase UI, and transaction updates in `BoardStoreClient`. Move entitlement ownership into `EntitlementReconciler`. `BoardStore.isUnlocked` updates from server entitlement/cache events. Remove the startup path that permanently unlocks solely because `Transaction.currentEntitlements` contains the product.

- [ ] **Step 7: Run entitlement tests**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/AccountEntitlementAPITests \
  -only-testing:CloveryTests/AccountEntitlementCacheTests \
  -only-testing:CloveryTests/EntitlementReconcilerTests \
  -only-testing:CloveryTests/BoardStoreTests test
```

Expected: selected tests pass.

- [ ] **Step 8: Commit entitlement reconciliation**

```bash
git add Clovery/Features/Entitlements Clovery/BoardStore* Clovery/WebView.swift \
  CloveryTests Clovery.xcodeproj/project.pbxproj
git commit -m "feat(ios): bind purchases to Clovery accounts"
```

## Task 8: Pull the Vault, Restore Photos, and Continue Two-Way Sync

**Files:**
- Create: `Clovery/Features/Sync/Data/VaultSyncAPI.swift`
- Create: `Clovery/Features/Sync/Data/VaultAssetAPI.swift`
- Create: `Clovery/Features/Sync/Domain/InitialVaultPuller.swift`
- Create: `Clovery/Features/Sync/Domain/VaultAssetUploader.swift`
- Create: `Clovery/Features/Sync/Domain/VaultSyncCheckpointStore.swift`
- Create: `Clovery/Features/Sync/Domain/VaultSyncCoordinator.swift`
- Modify: `Clovery/WebView.swift`
- Modify: `Clovery/Clover Diary.html`
- Create: `CloveryTests/VaultSyncAPITests.swift`
- Create: `CloveryTests/VaultAssetAPITests.swift`
- Create: `CloveryTests/InitialVaultPullerTests.swift`
- Create: `CloveryTests/VaultAssetUploaderTests.swift`
- Create: `CloveryTests/VaultSyncCheckpointStoreTests.swift`
- Create: `CloveryTests/VaultSyncCoordinatorTests.swift`

- [ ] **Step 1: Write pagination and materialization tests**

Require:

```text
pull starts at persisted account/vault cursor
pages until has_more=false
changes apply in cursor order
same operation ID applies once
deleted journal change removes only matching entry
active change merges by entity ID without replacing unrelated local entries
cursor persists only after atomic local materialization
account/vault change uses separate cursor namespace
final cursor is submitted as bootstrap vault checkpoint
```

- [ ] **Step 2: Write legacy asset restore tests**

Using W8's verified migration asset listing:

```text
list source filename -> asset ID/hash/bytes
skip an existing local photo only when size and SHA match
download missing/corrupt photo through a fresh ticket
verify bytes and SHA before atomic move into Documents/photos
failed photo download leaves prior file and bootstrap pending
path traversal or invalid filename is rejected
```

- [ ] **Step 3: Write ongoing push, conflict, and retry tests**

Extend the Web bridge save payload with `deleted_ids`. The coordinator diffs each full local snapshot against an account/vault-scoped mirror and tests:

```text
new entry -> base revision 0 push
edited entry -> last server revision push
deleted ID -> deleted operation with empty payload
same snapshot twice -> no second operation
operation UUID persists before network and is reused after crash
applied decision updates local revision and cursor
server conflict preserves server entry and pushes local content as a deterministic conflict copy
100-operation batching and ordered retry
foreground activation pulls after last durable cursor
logout/account change cancels work and changes checkpoint namespace
```

No conflict handler may discard either the local payload or server snapshot.

- [ ] **Step 4: Write ongoing photo upload tests**

Before pushing an entry, upload every referenced local photo that lacks an account-vault asset checkpoint. Use a stable generated asset UUID and persist filename, SHA, bytes, and asset ID. Add a private payload object:

```json
{
  "clovery_asset_refs": {
    "photo-0001.jpg": {
      "asset_id": "44444444-4444-4444-8444-444444444444",
      "sha256": "64-lowercase-hex",
      "byte_size": 1024
    }
  }
}
```

The visible `photos` array remains filenames for WebView compatibility. Another device verifies and downloads refs before materialization. Failed photo upload blocks that entry push and never strips the local photo.

- [ ] **Step 5: Run focused tests and observe missing implementation**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/VaultSyncAPITests \
  -only-testing:CloveryTests/VaultAssetAPITests \
  -only-testing:CloveryTests/InitialVaultPullerTests \
  -only-testing:CloveryTests/VaultAssetUploaderTests \
  -only-testing:CloveryTests/VaultSyncCheckpointStoreTests \
  -only-testing:CloveryTests/VaultSyncCoordinatorTests test
```

Expected: new tests fail.

- [ ] **Step 6: Implement typed push, pull, and asset clients**

Use authenticated Clovery API requests for `/v1/vault/sync/push`, sync pages, asset mappings, upload tickets, upload completion, and download tickets. Download/upload object bytes without Clovery bearer credentials, copy only required object-storage headers, then verify SHA-256 and expected size locally.

- [ ] **Step 7: Materialize into the existing diary store**

Extract the full-backup merge/write logic from `WebView` into a shared atomic store. The puller treats `sync_changes.entity_id` as authoritative and overwrites each materialized payload's `id` with that entity ID before writing `clovery_full_backup.json`; this makes server conflict copies editable in the existing WebView without changing their stored legacy comparison payload. It downloads `clovery_asset_refs`, removes no local-only entry until its operation is applied, then injects the merged result into WebView. Do not write diary content to logs or UserDefaults.

- [ ] **Step 8: Stop old cloud channels from becoming a second data root**

After account bootstrap starts, configure WebView in `accountVault` mode:

- continue atomic local backup and Widget snapshot writes;
- stop CloudKit pull/push and iCloud KVS diary merge/write for authenticated account data;
- leave all pre-existing CloudKit/KVS data untouched as recovery evidence;
- route every new/edit/delete event through `VaultSyncCoordinator`;
- resume pull on foreground, after a successful push, and on the coordinator's bounded background refresh schedule where iOS grants execution time.

The HTML receives this mode through a native bridge value, not a user-editable localStorage flag. Tests prove logging into another Clovery account on the same Apple device cannot import the previous account's old CloudKit data.

- [ ] **Step 9: Confirm the initial server checkpoint**

After the last page and asset verification, call bootstrap `resume` with `vault_checkpoint.cursor` and `has_more=false`. Enter diary only when the returned overall bootstrap status is `complete`.

- [ ] **Step 10: Start durable ongoing sync after diary entry**

After `.diary(accountID:vaultID:)`, keep one coordinator alive for that account/vault. It serializes local diffs, asset uploads, push decisions, and pulls. A bootstrap-complete job stays complete, but sync errors show the existing non-destructive sync status and retry automatically; they never silently fall back to CloudKit as the account data source.

- [ ] **Step 11: Run sync tests**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/VaultSyncAPITests \
  -only-testing:CloveryTests/VaultAssetAPITests \
  -only-testing:CloveryTests/InitialVaultPullerTests \
  -only-testing:CloveryTests/VaultAssetUploaderTests \
  -only-testing:CloveryTests/VaultSyncCheckpointStoreTests \
  -only-testing:CloveryTests/VaultSyncCoordinatorTests \
  -only-testing:CloveryTests/WebBridgeContractTests test
```

Expected: selected tests pass.

- [ ] **Step 12: Commit account-vault synchronization**

```bash
git add Clovery/Features/Sync Clovery/WebView.swift 'Clovery/Clover Diary.html' CloveryTests \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat(ios): synchronize the account vault"
```

## Task 9: Add Chinese Reconciliation UI and Integrate the Pipeline

**Files:**
- Create: `Clovery/Features/Bootstrap/Presentation/AccountReconciliationView.swift`
- Modify: `Clovery/Application/Bootstrap/AccountBootstrapCoordinator.swift`
- Modify: `Clovery/Application/Bootstrap/BootstrapDependencies.swift`
- Modify: `Clovery/Application/ApplicationRootView.swift`
- Modify: `Clovery/CloveryApp.swift`
- Modify: `Clovery/WebView.swift`
- Create: `CloveryTests/AccountReconciliationPresentationTests.swift`
- Modify: `CloveryTests/AccountBootstrapCoordinatorTests.swift`
- Modify: `CloveryTests/AuthenticationResourcesTests.swift`

- [ ] **Step 1: Write end-to-end coordinator tests with fakes**

Test sequences:

```text
legacy notice -> Apple claim -> CloveryID creation -> migration -> entitlement -> vault -> diary
legacy notice -> password login -> same pipeline
new install -> registration -> migration already complete -> entitlement -> vault -> diary
valid session restart during migration -> resumes same checkpoint
kill/restart after entitlement -> skips completed stage
temporary network failure -> retry, no diary
cross-account migration checkpoint -> support state, no upload
logout cancels in-flight tasks and clears account entitlement presentation
new diary after bootstrap pushes to Vault and returns on a second client pull
same Apple iCloud with a different Clovery account does not import old CloudKit data
```

- [ ] **Step 2: Build the reconciliation view in existing style**

Chinese copy and stages:

```text
正在整理你的 Clovery
正在确认账户
正在安全保存日记与照片
正在恢复已购权益
正在同步云端内容
```

Use `Color.authBackground`, `Color.authSurface`, dashed rounded borders, the clover hero asset, and `.cloveryFont`. Provide only safe actions:

```text
重试
退出账户
联系支持（带短支持编号，不含账户/日记/交易明文）
```

No stage can be skipped. Dynamic Type, VoiceOver labels, Reduce Motion, and small-screen scrolling must work.

- [ ] **Step 3: Integrate dependencies**

`BootstrapDependencies` creates one shared base `APIClient`, authenticated client, auth APIs, bootstrap API, migration coordinator, entitlement reconciler, and vault puller. Do not instantiate duplicate `BoardStore`, session stores, or migration checkpoint stores in child views.

- [ ] **Step 4: Remove old direct entitlement refresh hooks**

Replace `CloveryApp` scene activation calls that directly read local StoreKit with account-aware reconciliation/update handling. Keep transaction update observation, but route updates through the authenticated entitlement reconciler.

- [ ] **Step 5: Verify global font propagation**

Ensure authentication, identity claim, update notice, reconciliation, and diary overlays all inherit `fontStore.selection`. Add presentation tests or source contract assertions that no new screen uses hard-coded custom fonts outside `.cloveryFont`/environment.

- [ ] **Step 6: Register all sources and run focused integration tests**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:CloveryTests/AccountBootstrapCoordinatorTests \
  -only-testing:CloveryTests/AccountReconciliationPresentationTests \
  -only-testing:CloveryTests/AuthenticationResourcesTests test
```

Expected: selected tests pass.

- [ ] **Step 7: Run the complete simulator test suite and build**

```bash
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -resultBundlePath /private/tmp/Clovery-W9.xcresult test
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -configuration Release -destination 'generic/platform=iOS Simulator' build
git diff --check
```

Expected: all XCTest cases pass, Release simulator build exits `0`, and `git diff --check` prints nothing. If existing test-infrastructure failures remain, fix them in W10 before claiming release readiness; do not suppress tests.

- [ ] **Step 8: Commit integrated iOS bootstrap**

```bash
git add Clovery CloveryTests Clovery.xcodeproj/project.pbxproj
git commit -m "feat(ios): complete account inheritance bootstrap"
```

## Task 10: Verify W9 as an Independent Deliverable

**Files:**
- Create: `docs/superpowers/verification/2026-07-19-w9-ios-account-bootstrap.md`

- [ ] **Step 1: Install and launch a clean simulator build**

```bash
xcrun simctl boot 'iPhone 16 Pro' || true
xcodebuild -project Clovery.xcodeproj -scheme Clovery \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /private/tmp/Clovery-W9-DerivedData build
xcrun simctl install booted \
  /private/tmp/Clovery-W9-DerivedData/Build/Products/Debug-iphonesimulator/Clovery.app
xcrun simctl launch --console booted com.clovery.app
```

Expected: app remains running and shows Chinese authentication after loading on clean install.

- [ ] **Step 2: Run simulator fixture matrix**

Use debug-only launch fixtures or injected test dependencies, never production flags, to capture:

```text
clean install authentication
legacy mandatory notice
Apple + Google provider row only
identity claim CloveryID creation
migration progress
entitlement progress
needs-attention screen
final diary route
```

Repeat at default and largest accessibility text sizes and with each available Clovery font selection.

- [ ] **Step 3: Record acceptance evidence**

The verification document must include:

- tested commit SHA;
- test and Release build commands/exit codes;
- simulator model/iOS runtime;
- screenshots for the route matrix;
- proof that diary is unreachable while any bootstrap stage is incomplete;
- migration checkpoint persistence evidence;
- post-bootstrap push/pull and conflict-copy evidence;
- confirmation that authenticated diary sync no longer reads or writes old CloudKit/KVS as its data root;
- server entitlement and BoardStore state evidence with transaction IDs redacted;
- source-file size check confirming modular boundaries;
- confirmation that local legacy sources and archives still exist after success.

- [ ] **Step 4: Commit and push W9**

```bash
git add docs/superpowers/verification/2026-07-19-w9-ios-account-bootstrap.md
git commit -m "test(ios): verify account bootstrap flow"
git push origin codex/swift-auth-foundation
```

Expected: remote branch contains W9 and the working tree is clean.

## W9 Non-Goals

- Do not start Flutter or replace the WebView diary in this workflow.
- Do not implement Huawei UI on iOS.
- Do not expose Passkey as a first-screen quick-login button.
- Do not infer account ownership from email or device model.
- Do not unlock paid content permanently from local StoreKit state alone.
- Do not delete any old local, iCloud, CloudKit, photo, or migration data.
- Do not claim physical-device completion; W10 owns that explicit gate.
