# Swift iOS Authentication Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a production-shaped native Swift authentication and legacy-upgrade flow that preserves the Figma visual language while matching the existing Go account, session, provider, Passkey, and recovery contracts.

**Architecture:** Keep the existing WebView diary intact behind a small application route controller. Add focused SwiftUI authentication views, a typed URLSession client, Keychain-backed refresh sessions, provider adapters, and a non-destructive legacy-upgrade notice. Update the Go password policy and OpenAPI contract together so both clients accept passwords from 8 to 256 Unicode characters.

**Tech Stack:** Swift 5, SwiftUI, XCTest, URLSession, URLProtocol, Security/Keychain, AuthenticationServices, Go, Chi, PostgreSQL-backed existing auth services, OpenAPI 3.1.

---

## Scope and File Map

The implementation uses the dedicated worktree:

```text
/Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation
```

The existing native app remains the V1 diary host:

```text
Clovery/CloveryApp.swift
Clovery/ContentView.swift
Clovery/WebView.swift
```

New Swift files are grouped by responsibility:

```text
Clovery/
├── Application/
│   ├── ApplicationRootView.swift
│   ├── ApplicationSessionController.swift
│   └── LegacyUpgradeController.swift
├── Core/
│   ├── Configuration/APIConfiguration.swift
│   ├── Networking/APIClient.swift
│   ├── Networking/APIError.swift
│   ├── Networking/APIRequest.swift
│   ├── Security/DeviceIdentityStore.swift
│   ├── Security/KeychainStore.swift
│   └── Security/AuthenticationSessionStore.swift
├── Features/
│   ├── Authentication/
│   │   ├── Data/AuthenticationAPI.swift
│   │   ├── Data/AuthenticationModels.swift
│   │   ├── Domain/AuthenticationState.swift
│   │   ├── Domain/AuthenticationValidation.swift
│   │   ├── Presentation/AuthenticationEntryView.swift
│   │   ├── Presentation/LoginView.swift
│   │   ├── Presentation/LoginViewModel.swift
│   │   ├── Presentation/SignUpView.swift
│   │   ├── Presentation/SignUpViewModel.swift
│   │   ├── Presentation/RecoveryCodesView.swift
│   │   ├── Presentation/AccountRecoveryView.swift
│   │   ├── Presentation/AuthenticationTheme.swift
│   │   ├── Presentation/AuthenticationAssets.swift
│   │   └── Providers/
│   │       ├── AppleAuthenticationProvider.swift
│   │       ├── PasskeyAuthenticationProvider.swift
│   │       └── WebAuthenticationProvider.swift
│   └── Upgrade/
│       ├── LegacyDataDetector.swift
│       └── UpgradeNoticeView.swift
└── Assets.xcassets/
    ├── AuthCloverHero.imageset
    ├── AuthProviderApple.imageset
    ├── AuthProviderGoogle.imageset
    ├── AuthProviderHuawei.imageset
    ├── AuthProviderClovery.imageset
    ├── AuthBackArrow.imageset
    ├── AuthDivider.imageset
    ├── AuthBackground.colorset
    ├── AuthSurface.colorset
    ├── AuthInk.colorset
    ├── AuthPlaceholder.colorset
    └── AuthDashedBorder.colorset
```

The synchronized `CloveryTests` group automatically includes new test files. The application target is manually listed in `Clovery.xcodeproj/project.pbxproj`; every new application Swift file must be added to the `Clovery` group and `PBXSourcesBuildPhase`.

## API Contract Matrix

The typed Swift client must send and decode these exact routes:

| Feature | Method | Path | Request/response requirement |
| --- | --- | --- | --- |
| Register | POST | `/v1/auth/accounts` | Sends `login_id`, `password`, `recovery_method: recovery_codes`, and `device`; decodes tokens, account, vault, and eight recovery codes. |
| Password login | POST | `/v1/auth/password/login` | Sends `login_id`, `password`, and `device`; decodes tokens, account, and vault. |
| Refresh | POST | `/v1/auth/sessions/refresh` | Sends only the Keychain refresh token; replaces the stored refresh token on success. |
| Federated start | POST | `/v1/auth/federated/{provider}/start` | Decodes `intent_id`, `provider`, `nonce`, and `expires_in`. |
| Federated complete | POST | `/v1/auth/federated/{provider}/complete` | Sends intent, nonce, authorization code, and device; decodes an auth session. |
| Passkey start | POST | `/v1/auth/passkeys/login/start` | Decodes challenge ID and WebAuthn options. |
| Passkey complete | POST | `/v1/auth/passkeys/login/complete` | Sends challenge ID, WebAuthn response, and device; decodes an auth session. |
| Reset start | POST | `/v1/auth/password/reset/start` | Sends Clovery ID and `recovery_code`; maps the generic accepted response. |
| Recovery consume | POST | `/v1/auth/recovery-codes/consume` | Sends Clovery ID and one recovery code; decodes reset proof. |
| Reset complete | POST | `/v1/auth/password/reset/complete` | Sends reset intent, proof, and new password. |

The API error envelope is always decoded as:

```swift
struct APIErrorPayload: Decodable {
    let code: String
    let message: String
}
```

The client maps `invalid_credentials` to one generic authentication message, `login_id_unavailable` to a Clovery ID availability message, `identity_not_bound` to the safe binding explanation, and `rate_limited` to a retry message. It never exposes backend internals or whether an account exists.

## Task 1: Lower the Go Password Minimum and Contract

**Files:**
- Modify: `v2/services/api/internal/auth/password_test.go`
- Modify: `v2/services/api/internal/auth/password.go`
- Modify: `v2/services/api/internal/auth/password_test.go`
- Modify: `v2/contracts/openapi/openapi.yaml:937-998`
- Test: `v2/services/api/internal/auth/password_test.go`
- Test: existing `v2/services/api/internal/contract` tests

- [ ] **Step 1: Write the failing password-boundary tests**

Add explicit cases that prove the requested boundary:

```go
func TestPasswordPolicyAcceptsEightCharacters(t *testing.T) {
    if err := ValidatePassword("eight888"); err != nil {
        t.Fatalf("8-character password rejected: %v", err)
    }
}

func TestPasswordPolicyRejectsSevenCharacters(t *testing.T) {
    if err := ValidatePassword("seven77"); !errors.Is(err, ErrWeakPassword) {
        t.Fatalf("7-character password error = %v", err)
    }
}
```

Add common eight-character weak values to the existing blacklist test without changing the generic error:

```go
for _, password := range []string{
    "short",
    "seven77",
    "password",
    "12345678",
    "qwertyui",
    "clovery1",
    "password1234",
    "123456789012",
    "clovery12345",
} {
    // existing assertion remains ErrWeakPassword
}
```

- [ ] **Step 2: Run the focused tests and verify the new boundary fails**

Run:

```bash
cd /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/v2/services/api
GOCACHE=/private/tmp/clovery-go-build go test ./internal/auth -run 'TestPasswordPolicy'
```

Expected: the eight-character acceptance test fails because `ValidatePassword` still requires 12 characters.

- [ ] **Step 3: Implement the minimum change**

Change only the policy boundary and weak-password set:

```go
if passwordLength < 8 || passwordLength > 256 {
    return ErrWeakPassword
}
```

Update the OpenAPI password schemas so both account creation and reset use `minLength: 8`. Do not change Argon2id parameters, hash encoding, session behavior, or existing password rows.

- [ ] **Step 4: Run the focused and contract tests**

Run:

```bash
cd /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/v2/services/api
GOCACHE=/private/tmp/clovery-go-build go test ./internal/auth ./internal/application/authflow ./internal/http ./internal/contract
```

Expected: all packages pass, including the 8-character boundary and OpenAPI contract checks.

- [ ] **Step 5: Commit the backend contract change**

```bash
git add v2/services/api/internal/auth/password.go \
  v2/services/api/internal/auth/password_test.go \
  v2/contracts/openapi/openapi.yaml
git commit -m "feat: accept eight-character Clovery passwords"
```

## Task 2: Add Typed Swift API Transport

**Files:**
- Create: `Clovery/Core/Configuration/APIConfiguration.swift`
- Create: `Clovery/Core/Networking/APIError.swift`
- Create: `Clovery/Core/Networking/APIRequest.swift`
- Create: `Clovery/Core/Networking/APIClient.swift`
- Create: `Clovery/Features/Authentication/Data/AuthenticationModels.swift`
- Create: `Clovery/Features/Authentication/Data/AuthenticationAPI.swift`
- Create: `CloveryTests/AuthenticationAPIClientTests.swift`

- [ ] **Step 1: Write URLProtocol-backed request tests**

Create tests that intercept requests without a live server and assert exact method, path, headers, and JSON:

```swift
func testRegisterSendsRecoveryCodesAndDevice() async throws {
    let response = AuthSessionResponse(
        accountID: "account",
        vaultID: "vault",
        accessToken: "access",
        accessTokenExpiresIn: 900,
        refreshToken: "refresh",
        recoveryCodes: ["one", "two"]
    )
    let client = makeClient(response: response)

    let result = try await client.register(
        loginID: "clovery_user",
        password: "eight888",
        device: DeviceRegistration(
            deviceID: "device",
            platform: "ios",
            displayName: "Test iPhone"
        )
    )

    XCTAssertEqual(result.vaultID, "vault")
    XCTAssertEqual(lastRequest?.httpMethod, "POST")
    XCTAssertEqual(lastRequest?.url?.path, "/v1/auth/accounts")
    XCTAssertEqual(lastJSON?["recovery_method"] as? String, "recovery_codes")
}
```

Add tests for password login, refresh-token rotation, federated start/complete, passkey start/complete, error-envelope decoding, and bearer authorization.

- [ ] **Step 2: Run tests to verify the transport types are missing**

Run:

```bash
xcodebuild test \
  -project /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/Clovery.xcodeproj \
  -scheme Clovery \
  -destination 'generic/platform=iOS'
```

Expected: compilation fails because the typed API models and client do not exist yet.

- [ ] **Step 3: Implement focused transport types**

Define Codable models with explicit snake-case keys. Use a single `APIRequest` value for method, path, body, and bearer-token requirement. `APIClient` must:

```swift
struct APIConfiguration {
    let baseURL: URL
}

protocol APITransport {
    func send<Response: Decodable>(
        _ request: URLRequest,
        decoding: Response.Type
    ) async throws -> Response
}
```

Use `URLSession` as the production transport and `URLProtocol` injection in tests. Reject non-HTTPS Release URLs in `APIConfiguration`. Do not log request bodies.

- [ ] **Step 4: Run the focused Swift tests**

Run the same `xcodebuild test` command and expect the request tests to pass. If the local simulator service is unavailable, run the generic iOS build and retain the exact simulator limitation for the final verification report.

- [ ] **Step 5: Commit the transport layer**

```bash
git add Clovery/Core Clovery/Features/Authentication/Data CloveryTests/AuthenticationAPIClientTests.swift Clovery.xcodeproj/project.pbxproj
git commit -m "feat: add typed Swift authentication transport"
```

## Task 3: Add Keychain Device and Session Storage

**Files:**
- Create: `Clovery/Core/Security/KeychainStore.swift`
- Create: `Clovery/Core/Security/DeviceIdentityStore.swift`
- Create: `Clovery/Core/Security/AuthenticationSessionStore.swift`
- Create: `CloveryTests/KeychainStoreTests.swift`
- Create: `CloveryTests/DeviceIdentityStoreTests.swift`
- Create: `CloveryTests/AuthenticationSessionStoreTests.swift`

- [ ] **Step 1: Write storage behavior tests**

Cover:

```swift
func testDeviceIDIsStableAcrossReads() throws {
    let first = try store.deviceID()
    let second = try store.deviceID()
    XCTAssertEqual(first, second)
}

func testSessionStoreReplacesRefreshTokenAtomically() throws {
    try sessionStore.save(session: makeSession(refreshToken: "old"))
    try sessionStore.replaceRefreshToken("new")
    XCTAssertEqual(try sessionStore.refreshToken(), "new")
}

func testClearingSessionDoesNotClearLegacyDataMarker() throws {
    try sessionStore.clear()
    XCTAssertTrue(legacyMarkerStore.stillContainsData)
}
```

Use an injectable Keychain service/account namespace in tests so tests remove only their own items.

- [ ] **Step 2: Run the tests to verify failure**

Run:

```bash
xcodebuild test \
  -project /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/Clovery.xcodeproj \
  -scheme Clovery \
  -destination 'generic/platform=iOS'
```

Expected: the new storage test target files fail to compile until the storage types exist.

- [ ] **Step 3: Implement secure storage**

Use `Security` with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` for the refresh token and device ID. Store only:

```text
com.clovery.auth.refresh-token
com.clovery.auth.device-id
```

Keep access token, account ID, vault ID, and expiry in an in-memory `AuthenticationSession`. Never use `UserDefaults`, Drift, the WebView, or App Group storage for secrets.

- [ ] **Step 4: Run storage tests and inspect Keychain cleanup**

Run the focused tests and verify the test teardown deletes the test namespace. Confirm the production clear path removes refresh token but does not touch diary backups, CloudKit markers, or photos.

- [ ] **Step 5: Commit storage**

```bash
git add Clovery/Core/Security CloveryTests/KeychainStoreTests.swift \
  CloveryTests/DeviceIdentityStoreTests.swift \
  CloveryTests/AuthenticationSessionStoreTests.swift \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat: store authentication credentials in Keychain"
```

## Task 4: Implement Validation and Authentication View Models

**Files:**
- Create: `Clovery/Features/Authentication/Domain/AuthenticationState.swift`
- Create: `Clovery/Features/Authentication/Domain/AuthenticationValidation.swift`
- Create: `Clovery/Features/Authentication/Presentation/LoginViewModel.swift`
- Create: `Clovery/Features/Authentication/Presentation/SignUpViewModel.swift`
- Create: `Clovery/Application/ApplicationSessionController.swift`
- Create: `CloveryTests/AuthenticationValidationTests.swift`
- Create: `CloveryTests/LoginViewModelTests.swift`
- Create: `CloveryTests/SignUpViewModelTests.swift`

- [ ] **Step 1: Write validation and view-model tests**

The tests must prove:

```swift
func testCloveryIDNormalizesToLowercase() {
    XCTAssertEqual(
        AuthenticationValidation.normalizedCloveryID("  Clovery_User "),
        "clovery_user"
    )
}

func testCloveryIDRejectsEmailAddress() {
    XCTAssertFalse(AuthenticationValidation.isValidCloveryID("user@example.com"))
}

func testEightCharacterPasswordIsValid() {
    XCTAssertTrue(AuthenticationValidation.isValidPassword("eight888"))
}

func testMismatchedConfirmationBlocksRegistration() async {
    viewModel.password = "eight888"
    viewModel.confirmPassword = "different"
    await viewModel.submit()
    XCTAssertEqual(viewModel.validationError, .passwordsDoNotMatch)
    XCTAssertFalse(api.didRegister)
}
```

Add tests for duplicate submission, generic invalid credentials, rate limits, login-ID conflicts, cancellation, and recovery-code output.

- [ ] **Step 2: Run the tests and verify they fail**

Run the focused Swift tests using the existing `Clovery` scheme. Expected: the new types are missing or the behavior assertions fail.

- [ ] **Step 3: Implement domain validation and view models**

Use a compiled regex matching the server's Clovery ID rule:

```swift
^[a-z][a-z0-9_]{3,23}$
```

Use an 8–256 Unicode scalar/rune boundary consistent with the Go server. The view models call `AuthenticationAPI`, set `isSubmitting`, map `APIError`, pass returned sessions to `ApplicationSessionController`, and retain registration recovery codes only until the recovery-code screen acknowledges them.

- [ ] **Step 4: Run focused tests**

Run:

```bash
xcodebuild test \
  -project /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/Clovery.xcodeproj \
  -scheme Clovery \
  -destination 'generic/platform=iOS'
```

Expected: validation and view-model tests pass with no token or password output.

- [ ] **Step 5: Commit view-model behavior**

```bash
git add Clovery/Features/Authentication/Domain \
  Clovery/Features/Authentication/Presentation/LoginViewModel.swift \
  Clovery/Features/Authentication/Presentation/SignUpViewModel.swift \
  Clovery/Application/ApplicationSessionController.swift \
  CloveryTests/AuthenticationValidationTests.swift \
  CloveryTests/LoginViewModelTests.swift \
  CloveryTests/SignUpViewModelTests.swift \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat: add Swift authentication validation and state"
```

## Task 5: Add Figma Assets, Font Registration, and Shared Theme

**Files:**
- Create/modify: `Clovery/Assets.xcassets/Auth*.imageset/*`
- Create/modify: `Clovery/Assets.xcassets/Auth*.colorset/*`
- Create: `Clovery/Features/Authentication/Presentation/AuthenticationTheme.swift`
- Create: `Clovery/Features/Authentication/Presentation/AuthenticationAssets.swift`
- Modify: `Clovery/Info.plist`
- Modify: `Clovery.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add asset validation before UI code**

Create a resource test or asset lookup test that asserts these names resolve from the main bundle:

```swift
for name in [
    "AuthCloverHero",
    "AuthProviderApple",
    "AuthProviderGoogle",
    "AuthProviderHuawei",
    "AuthProviderClovery",
    "AuthBackArrow",
    "AuthDivider"
] {
    XCTAssertNotNil(UIImage(named: name))
}
```

- [ ] **Step 2: Verify the test fails before asset import**

Run the focused resource test and expect missing-image failures.

- [ ] **Step 3: Download and normalize the approved Figma assets**

Download the approved short-lived Figma assets into temporary files, inspect them, then import only the required PNG/SVG bytes into named asset sets. Use these source asset IDs:

```text
Entry clover: d67ebab7-21c6-46d1-8896-f6c0cff27457
Sign-up Apple: a7ef9d1b-9c41-45f2-ad40-2649575b7f71
Sign-up Google: 15ae584e-1902-4d6d-8725-b41e8a34dc00
Sign-up Huawei: cb760c20-1170-4553-a37b-412c6ee6a4bb
Sign-up Clovery: 9434c64f-244d-4237-9760-b820f8dc055e
Login Apple: fe7d6a65-5168-44c4-b78e-3979b0c27bb4
Login Google: e076864f-817c-4f2e-90fe-987a1f01042e
Login Huawei: 1a93412b-7ad0-463f-a0b5-85271bf2fc6d
Login Clovery: 4f94fad8-cbf8-4674-b486-fc5c9365f67a
Sign-up arrow: 84f79709-9717-4537-90c6-ed68167440cb
Login arrow: 10580db7-203e-44fd-bf40-f537e6c3c76e
Sign-up divider: c49a242e-3551-480a-bed0-0a2102999f25
Login divider: 63859048-34ac-418e-9a1c-46b8dcae8656
```

Do not retain Figma URLs in production code.

- [ ] **Step 4: Register Gaegu and define named theme tokens**

Add `UIAppFonts` entries for the bundled `fonts/Gaegu-Regular.ttf`, `fonts/Gaegu-Light.ttf`, and `fonts/Gaegu-Bold.ttf`. Define `Color.authBackground`, `Color.authSurface`, `Color.authInk`, `Color.authPlaceholder`, and `Color.authDashedBorder` from named asset colors. Define `Font.authTitle`, `Font.authBody`, and `Font.authCaption` using `Font.custom("Gaegu-Regular", size: ..., relativeTo: ...)`.

- [ ] **Step 5: Run the resource and font checks**

Verify the named assets resolve and `UIFont(name: "Gaegu-Regular", size: 24)` resolves from the application bundle. If the font's PostScript name differs, use the inspected PostScript name in the shared theme and keep the file name in `UIAppFonts`.

- [ ] **Step 6: Commit theme and assets**

```bash
git add Clovery/Assets.xcassets Clovery/Info.plist \
  Clovery/Features/Authentication/Presentation/AuthenticationTheme.swift \
  Clovery/Features/Authentication/Presentation/AuthenticationAssets.swift \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat: add Figma authentication assets and theme"
```

## Task 6: Reproduce the Three SwiftUI Screens

**Files:**
- Create: `Clovery/Features/Authentication/Presentation/AuthenticationEntryView.swift`
- Create: `Clovery/Features/Authentication/Presentation/LoginView.swift`
- Create: `Clovery/Features/Authentication/Presentation/SignUpView.swift`
- Create: `Clovery/Features/Authentication/Presentation/RecoveryCodesView.swift`
- Create: `Clovery/Features/Authentication/Presentation/Components/AuthDashedCard.swift`
- Create: `Clovery/Features/Authentication/Presentation/Components/AuthCapsuleField.swift`
- Create: `Clovery/Features/Authentication/Presentation/Components/AuthProviderButton.swift`
- Create: `Clovery/Features/Authentication/Presentation/Components/AuthDivider.swift`
- Modify: `Clovery.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add view-level routing tests**

Test that the entry flow produces the expected destinations through state, without depending on pixel snapshots:

```swift
func testEntryActionRoutesToLogin() {
    var route = AuthenticationRoute.entry
    route = .login
    XCTAssertEqual(route, .login)
}
```

Add accessibility-label assertions for login, sign-up, Apple, Google, Huawei, and Passkey actions in the view model/component test layer.

- [ ] **Step 2: Verify the route tests fail before screen implementation**

Run the focused Swift test command and expect missing route/component symbols.

- [ ] **Step 3: Implement shared layout components**

Use SwiftUI layout primitives rather than translating Figma absolute positions:

```swift
struct AuthCapsuleField<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 36)
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(Color.authSurface, in: Capsule())
    }
}
```

The dashed card uses a `RoundedRectangle` stroke with dash pattern `[8, 8]`, 2 pt line width, and the exact 60 pt corner radius. Provider buttons use the approved icon assets and 49 pt visual size while maintaining a 44 pt minimum hit area.

- [ ] **Step 4: Implement entry, sign-up, and login views**

Use a `NavigationStack` for the linear auth flow. The entry screen keeps the clover hero and two action capsules. Sign-up uses Clovery ID/password/confirmation fields and a primary action. Login uses Clovery ID/password, the provider row, recovery link, and sign-up link. The views receive view models and API/provider dependencies through initializers; no network request is created inside `body`.

- [ ] **Step 5: Add the recovery-code handoff**

Render eight codes in a blocking branded view with copy/export affordances. The continuation button remains disabled until the user acknowledges that the codes were saved. The view model clears its in-memory code array after acknowledgement.

- [ ] **Step 6: Run build and inspect screenshots**

Run:

```bash
xcodebuild build \
  -project /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/Clovery.xcodeproj \
  -scheme Clovery \
  -configuration Debug \
  -destination 'generic/platform=iOS'
```

Render the three screens on a 402 × 874 iPhone simulator when CoreSimulator is available and compare against the downloaded Figma screenshots. Adjust only layout constants, not the approved visual tokens.

- [ ] **Step 7: Commit the screen implementation**

```bash
git add Clovery/Features/Authentication/Presentation \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat: reproduce native Swift authentication screens"
```

## Task 7: Add Provider and Recovery Adapters

**Files:**
- Create: `Clovery/Features/Authentication/Providers/AppleAuthenticationProvider.swift`
- Create: `Clovery/Features/Authentication/Providers/PasskeyAuthenticationProvider.swift`
- Create: `Clovery/Features/Authentication/Providers/WebAuthenticationProvider.swift`
- Create: `Clovery/Features/Authentication/Presentation/AccountRecoveryView.swift`
- Create: `CloveryTests/ProviderAuthenticationTests.swift`
- Create: `CloveryTests/AccountRecoveryViewModelTests.swift`

- [ ] **Step 1: Write provider and recovery tests**

Cover:

```swift
func testAppleCancellationDoesNotShowAuthenticationError() async {
    let result = await provider.complete(.cancelled)
    XCTAssertEqual(result, .cancelled)
}

func testRecoveryCodeFlowConsumesCodeBeforeCompletingReset() async throws {
    try await recovery.reset(
        loginID: "clovery_user",
        recoveryCode: "one-time-code",
        newPassword: "eight888"
    )
    XCTAssertEqual(api.calls, [
        .consumeRecoveryCode,
        .completePasswordReset
    ])
}
```

Add tests that the provider completion request preserves the server nonce and intent, and that `identity_not_bound` returns the binding-safe state rather than auto-creating a second account.

- [ ] **Step 2: Run tests to verify missing adapters**

Run the focused Swift test command and confirm the new provider protocols and recovery behavior are absent.

- [ ] **Step 3: Implement Apple and Passkey adapters**

Use `AuthenticationServices`:

- Apple uses `ASAuthorizationAppleIDProvider` and sends the authorization code as the backend completion code.
- Passkey uses the challenge options returned by the Go API and completes with the serialized assertion response.
- Challenge state is in-memory and expires with the server response.

Define a provider protocol so views depend on behavior, not SDK classes.

- [ ] **Step 4: Implement the web OIDC adapter**

Use `ASWebAuthenticationSession` with build-configured provider authorization URLs, client IDs, redirect schemes, and callback handling. The adapter never receives provider client secrets. If a provider is not completely configured, return `.unavailable` and keep the UI stable.

- [ ] **Step 5: Implement recovery-code reset**

Use the existing Go flow:

```text
POST /v1/auth/recovery-codes/consume
POST /v1/auth/password/reset/complete
```

Keep the reset intent and proof in memory only. Enforce the same 8–256 password validation locally, then let the backend revoke prior sessions.

- [ ] **Step 6: Run provider/recovery tests and commit**

```bash
xcodebuild test \
  -project /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/Clovery.xcodeproj \
  -scheme Clovery \
  -destination 'generic/platform=iOS'
git add Clovery/Features/Authentication/Providers \
  Clovery/Features/Authentication/Presentation/AccountRecoveryView.swift \
  CloveryTests/ProviderAuthenticationTests.swift \
  CloveryTests/AccountRecoveryViewModelTests.swift \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat: connect provider and recovery authentication"
```

## Task 8: Add Root Routing and Legacy Upgrade Notice

**Files:**
- Create: `Clovery/Application/ApplicationRootView.swift`
- Create: `Clovery/Application/LegacyUpgradeController.swift`
- Create: `Clovery/Features/Upgrade/LegacyDataDetector.swift`
- Create: `Clovery/Features/Upgrade/UpgradeNoticeView.swift`
- Modify: `Clovery/ContentView.swift`
- Modify: `Clovery/CloveryApp.swift`
- Create: `CloveryTests/LegacyDataDetectorTests.swift`
- Create: `CloveryTests/LegacyUpgradeControllerTests.swift`

- [ ] **Step 1: Write routing and non-destructive upgrade tests**

Cover:

```swift
func testFreshInstallationWithoutSessionStartsAuthentication() {
    let route = controller.route(
        hasSession: false,
        hasLegacyData: false,
        hasAcknowledgedCurrentVersion: false
    )
    XCTAssertEqual(route, .authentication)
}

func testLegacyInstallationWithoutSessionStillStartsDiary() {
    let route = controller.route(
        hasSession: false,
        hasLegacyData: true,
        hasAcknowledgedCurrentVersion: false
    )
    XCTAssertEqual(route, .legacyDiaryWithUpgradeNotice)
}

func testDismissingNoticeDoesNotDeleteLegacyData() {
    controller.dismissNotice()
    XCTAssertTrue(detector.dataStillExists)
}
```

- [ ] **Step 2: Run tests to verify root routing is missing**

Run the focused Swift tests and confirm the new route and detector types are not present.

- [ ] **Step 3: Implement safe legacy detection**

Inspect only existing non-destructive markers:

```text
clovery_entries
clovery_entries_z
clovery_full_backup.json
clovery_backup.json
clovery_name
```

Also inspect the existing CloudKit key-value marker through the established `CloudKitSync` boundary. Do not load or rewrite diary contents during route selection.

- [ ] **Step 4: Implement versioned update notice**

Compare the current `CFBundleShortVersionString` with a separate `clovery_last_upgrade_notice_version` value. Present `UpgradeNoticeView` only after the legacy diary is visible. `LATER` records only the current notice version. `BIND CLOVERY ACCOUNT` opens authentication in binding mode and never deletes local data.

- [ ] **Step 5: Integrate the application root**

Change `ContentView` to delegate to `ApplicationRootView`. Preserve the existing `WebView().ignoresSafeArea()` route for legacy/authenticated diary access. `CloveryApp` continues to own CloudKit subscription and StoreKit lifecycle responsibilities.

- [ ] **Step 6: Run routing tests and commit**

```bash
xcodebuild test \
  -project /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/Clovery.xcodeproj \
  -scheme Clovery \
  -destination 'generic/platform=iOS'
git add Clovery/Application Clovery/Features/Upgrade \
  Clovery/ContentView.swift Clovery/CloveryApp.swift \
  CloveryTests/LegacyDataDetectorTests.swift \
  CloveryTests/LegacyUpgradeControllerTests.swift \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat: preserve legacy users during auth rollout"
```

## Task 9: Configure Build Environments and Verify the Full Slice

**Files:**
- Modify: `Clovery/Info.plist`
- Modify: `Clovery.xcodeproj/project.pbxproj`
- Create: `Config/Debug.xcconfig`
- Create: `Config/Release.xcconfig`
- Create: `CloveryTests/AuthenticationReleaseConfigurationTests.swift`
- Modify: `docs/superpowers/specs/2026-07-19-swift-auth-foundation-design.md` only if an implementation decision changes the approved contract

- [ ] **Step 1: Write release-configuration tests**

Prove Debug accepts `http://127.0.0.1:8080` and Release rejects non-HTTPS or staging API URLs. Prove provider availability is derived from build settings rather than embedded secrets.

- [ ] **Step 2: Implement build settings**

Add:

```text
CLOVERY_API_BASE_URL = http://127.0.0.1:8080
```

Put the Debug value in `Config/Debug.xcconfig`. Put the Release setting in `Config/Release.xcconfig` as an environment-injected `CLOVERY_RELEASE_API_BASE_URL` value, and make the release verification test fail when that value is empty, non-HTTPS, or points at the staging host documented in `v2/docs/release/backend-deployment.md`. The actual production API hostname is supplied by the release environment after backend provisioning; no unverified hostname is committed. Provider client IDs and redirect schemes remain build settings or protected CI values. No secret is committed.

- [ ] **Step 3: Run the complete automated verification**

Run:

```bash
cd /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation/v2/services/api
GOCACHE=/private/tmp/clovery-go-build go test ./...

cd /Users/huao/Downloads/Clovery-main/.worktrees/swift-auth-foundation
./scripts/test-v1-p0-contract.sh
xcodebuild build \
  -project Clovery.xcodeproj \
  -scheme Clovery \
  -configuration Debug \
  -destination 'generic/platform=iOS'
xcodebuild test \
  -project Clovery.xcodeproj \
  -scheme Clovery \
  -destination 'generic/platform=iOS'
git diff --check
git status --short
```

Expected: Go tests, V1 bridge contract, Swift compilation, Swift unit tests, and whitespace checks pass. A simulator-specific test report must call out any CoreSimulator service limitation rather than claiming a visual test passed.

- [ ] **Step 4: Perform simulator visual acceptance**

When a supported iPhone simulator is available, render:

```text
Entry: 402 × 874
Sign up: 402 × 874
Log in: 402 × 874
```

Compare against the downloaded Figma screenshots. Verify the changed labels are the only intentional visual content changes, and verify keyboard, Dynamic Type, VoiceOver, recovery-code, and error states.

- [ ] **Step 5: Create a release evidence note**

Record only:

- commit SHA
- test commands and pass/fail
- screen dimensions
- configured environment category
- provider configuration status

Never record passwords, tokens, recovery codes, authorization codes, diary text, image bytes, or Figma asset URLs.

- [ ] **Step 6: Commit and push the complete implementation**

```bash
git add Clovery CloveryTests Config Clovery.xcodeproj/project.pbxproj docs/superpowers/plans
git commit -m "feat: complete native Swift authentication flow"
git push -u origin codex/swift-auth-foundation
```

## Acceptance Checklist

- [ ] The three Figma screens render in native SwiftUI with Gaegu typography and preserved visual tokens.
- [ ] Registration sends custom Clovery ID and `recovery_codes`.
- [ ] Passwords from 8 to 256 characters follow the updated Go/OpenAPI policy.
- [ ] Registration displays eight recovery codes exactly once.
- [ ] Password login and refresh-token rotation work through the Go API.
- [ ] Apple, Google, Huawei, and Passkey adapters preserve backend intent/nonce semantics.
- [ ] Refresh token and device ID use Keychain; access token stays in memory.
- [ ] Existing users see the main diary first, then the update notice and binding prompt.
- [ ] Dismissal, logout, provider failure, or binding failure never deletes legacy data.
- [ ] Existing V1 bridge, photo export, StoreKit, CloudKit, migration, and release tests remain green.
- [ ] The implementation is pushed to `codex/swift-auth-foundation`.
- [ ] Real-device testing remains the next gate before Flutter work begins.
