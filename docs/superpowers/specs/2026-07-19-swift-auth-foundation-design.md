# Swift iOS Authentication Foundation Design

**Date:** 2026-07-19

**Status:** Approved for implementation

**Scope:** Native SwiftUI authentication and legacy-upgrade entry flow for the currently published iOS application. Flutter remains unchanged until the native iOS workflow is accepted.

## 1. Objectives

- Reproduce the three approved Figma screens in native SwiftUI.
- Preserve the Figma typography, colors, rounded geometry, dashed borders, icon treatment, and visual spacing.
- Adjust field labels and supporting interactions where the Go API contract requires different data.
- Connect registration, password login, session refresh, federated login, and Passkey login to the existing versioned Go API.
- Store long-lived credentials only in Keychain.
- Allow existing App Store users to enter the diary immediately after upgrading.
- Present existing users with a branded update notice and a non-destructive Clovery account binding prompt.
- Keep the work modular; no authentication or upgrade-flow file should become a general-purpose application container.

## 2. Non-Goals

- Do not begin the Flutter client rewrite.
- Do not replace the existing WebView diary implementation.
- Do not delete, rewrite, or move existing local diary or photo data during authentication.
- Do not silently merge Clovery accounts by email.
- Do not enable a provider in production until its client identifier, redirect configuration, backend OIDC configuration, and acceptance evidence are complete.
- Do not require real-device testing until the native iOS implementation is complete, as previously agreed.

## 3. Visual Contract

The source of truth is the three Figma frames:

- Entry: `284:340`
- Sign up: `284:364`
- Log in: `284:398`

The implementation preserves:

- Background: `#FAFAF6`
- Field and provider-button fill: `#F1F6ED`
- Primary ink: `#6B6B6B`
- Placeholder ink: `#C1C1C1`
- Dashed outline: `#A8A8A8`
- Font family: bundled `Gaegu-Regular`
- Main title size: 48 pt relative to a large-title Dynamic Type role
- Primary action and field text size: 24 pt relative to body/title roles
- Supporting text size: 16 pt relative to caption/footnote roles
- Large rounded field capsules and 60 pt dashed-card corner radius
- Four 49 pt provider tiles with 20 pt corner radius

The 402 × 874 Figma frame is the pixel-comparison reference. SwiftUI uses adaptive stacks, safe-area insets, keyboard-aware scrolling, and minimum tap targets rather than hard-coded absolute positions.

The existing bundled Gaegu font is registered for native SwiftUI use through `UIAppFonts`. All custom-font calls use `relativeTo:` so Dynamic Type remains functional.

## 4. Screen Flow

### 4.1 Authentication Entry

The entry screen keeps the clover illustration, dashed card, `LOG IN`, and `SIGN UP` actions.

- `LOG IN` pushes the password/federated login screen.
- `SIGN UP` pushes the Clovery account registration screen.
- The decorative clover is bundled in `Assets.xcassets`; the app never loads a Figma asset URL at runtime.

### 4.2 Sign Up

The Figma styling remains unchanged, but the three fields become:

1. `Clovery ID...`
2. `Password...`
3. `Confirm Password...`

The old `Email Address...` placeholder is not retained because the current Go API creates accounts using a user-selected Clovery ID.

Client validation mirrors the server:

- Clovery ID is normalized to lowercase.
- Clovery ID must match `^[a-z][a-z0-9_]{3,23}$`.
- Reserved IDs remain server-authoritative; the client maps `login_id_unavailable` to a generic availability message.
- Password length is 8–256 Unicode characters.
- Password and confirmation must match.
- Weak-password rejection remains server-authoritative and is mapped to a non-sensitive form error.

The request is:

```json
{
  "login_id": "custom_clovery_id",
  "password": "user supplied password",
  "recovery_method": "recovery_codes",
  "device": {
    "device_id": "stable keychain uuid",
    "platform": "ios",
    "display_name": "user-visible device name"
  }
}
```

The client calls `POST /v1/auth/accounts`.

The current backend only implements `recovery_codes` during account creation, even though the broader OpenAPI enum reserves future recovery methods. The iOS client therefore sends only `recovery_codes`.

On success:

1. Save the refresh token and stable device ID in Keychain.
2. Keep the access token in the in-memory session controller.
3. Keep `account_id`, `vault_id`, and access-token expiry as non-secret session metadata.
4. Present the eight one-time recovery codes in a branded, Gaegu-styled blocking sheet.
5. Require the user to confirm that the codes were saved before entering the diary.
6. Never write recovery codes to logs, analytics, screenshots, `UserDefaults`, or the WebView.

### 4.3 Log In

The fields become:

1. `Clovery ID...`
2. `Password...`

The client calls `POST /v1/auth/password/login` with the same device registration object used by account creation.

The server's generic `invalid_credentials` response maps to one generic message. The UI must not reveal whether a Clovery ID exists.

The four provider buttons map to:

1. Apple
2. Google
3. Huawei
4. Passkey, represented by the Figma clover icon

The provider row remains visually identical. A provider without complete build and backend configuration remains visible but disabled with an accessible “not available in this build” explanation; it must not fail silently.

A small Gaegu-styled recovery link is added without changing the field-card geometry. It opens the account-recovery workflow backed by the existing password-reset and recovery-code endpoints.

### 4.4 Federated Login

Apple, Google, and Huawei follow the backend two-step contract:

1. `POST /v1/auth/federated/{provider}/start`
2. Perform provider authorization using the returned nonce and the provider-specific native/web authorization adapter.
3. `POST /v1/auth/federated/{provider}/complete`

The completion request sends:

```json
{
  "intent_id": "server intent uuid",
  "nonce": "server nonce",
  "authorization_code": "provider authorization code",
  "device": {
    "device_id": "stable keychain uuid",
    "platform": "ios",
    "display_name": "user-visible device name"
  }
}
```

Provider identities are never merged by email. An `identity_not_bound` response presents two safe choices: return to login, or sign in to an existing Clovery account before binding the provider.

Provider adapters are separate files so Apple AuthenticationServices, Google authorization, and Huawei authorization do not share conditional logic in one view model.

### 4.5 Passkey Login

The clover provider button calls:

1. `POST /v1/auth/passkeys/login/start`
2. Perform the assertion using `AuthenticationServices`.
3. `POST /v1/auth/passkeys/login/complete`

Passkey challenge data remains in memory for the ceremony duration. The app never persists the challenge or assertion.

### 4.6 Session Refresh and Logout

- Access tokens remain in memory.
- Refresh tokens use a Keychain item accessible after first device unlock and unavailable to other apps.
- Refresh uses `POST /v1/auth/sessions/refresh`.
- A successful refresh atomically replaces the stored refresh token.
- An invalid or revoked refresh token clears the session credentials but does not delete local diary data.
- Logout clears authentication credentials and returns to the entry screen.
- Logout does not remove the device's legacy local data.

## 5. Password Policy Change

The product requirement changes the minimum password length from 12 to 8 characters.

The backend, OpenAPI, and iOS client change together:

- Go `ValidatePassword`: 8–256 Unicode characters.
- OpenAPI `CreateAccountRequest.password.minLength`: 8.
- OpenAPI reset password minimum: 8.
- iOS form validation: 8–256 Unicode characters.
- Existing Argon2id parameters and random salts remain unchanged.
- The weak-password blacklist is expanded for common eight-character passwords.
- Existing password hashes and accounts require no migration.

The server remains authoritative. Client validation exists for immediate feedback only.

## 6. Legacy App Store Upgrade Flow

Existing users must not be blocked by the new authentication gate.

### 6.1 Upgrade Detection

The application stores the last acknowledged app version separately from diary data.

On launch:

- A valid stored Clovery session enters the diary.
- An installation with legacy local/cloud diary evidence enters the diary even without a Clovery session.
- A fresh installation without a session or legacy data enters the authentication entry screen.

Legacy evidence checks existing non-destructive sources such as the Clovery backup files, iCloud key-value data markers, and existing persisted diary markers. Detection must not mutate them.

### 6.2 Update Notice

After the upgraded existing user reaches the main diary, the app presents an update sheet matching the application's visual language:

- `#FAFAF6` background
- Gaegu typography
- pale green rounded action surfaces
- gray dashed border
- friendly concise release explanation

The notice explains:

- Clovery accounts now protect cross-device access.
- Existing diary and photo data remain on the device.
- Binding an account does not delete local data.

Actions:

- Primary: `BIND CLOVERY ACCOUNT`
- Secondary: `LATER`

`LATER` dismisses the sheet and records only the notice acknowledgement for the current version. It does not mark the account as bound and does not alter diary data.

The binding prompt remains available from the app after dismissal.

### 6.3 Binding

The binding action presents the same authentication entry flow in legacy-binding mode.

- Existing Clovery users log in.
- New users create a custom Clovery ID.
- Authentication success associates the local app session with the returned `clovery_account_id` and `vault_id`.
- Local data remains authoritative and untouched until the separately validated migration/sync workflow imports it.
- Any future migration failure leaves the original local data and backup files intact.

## 7. Application Architecture

The native app root becomes a small state router instead of placing authentication logic in `ContentView.swift`.

```text
ApplicationRoot
├── legacy diary route
├── authenticated diary route
└── authentication route
    └── AuthenticationNavigationStack
        ├── AuthenticationEntryView
        ├── SignUpView
        ├── LoginView
        ├── RecoveryCodesView
        └── AccountRecoveryView
```

File responsibilities:

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
│   ├── Security/KeychainStore.swift
│   └── Security/DeviceIdentityStore.swift
├── Features/
│   ├── Authentication/
│   │   ├── Data/AuthenticationAPI.swift
│   │   ├── Data/AuthenticationModels.swift
│   │   ├── Data/AuthenticationSessionStore.swift
│   │   ├── Domain/AuthenticationValidation.swift
│   │   ├── Domain/AuthenticationState.swift
│   │   ├── Presentation/AuthenticationEntryView.swift
│   │   ├── Presentation/LoginView.swift
│   │   ├── Presentation/LoginViewModel.swift
│   │   ├── Presentation/SignUpView.swift
│   │   ├── Presentation/SignUpViewModel.swift
│   │   ├── Presentation/RecoveryCodesView.swift
│   │   └── Presentation/Components/
│   └── Upgrade/
│       ├── LegacyDataDetector.swift
│       └── UpgradeNoticeView.swift
└── Resources/
    └── authentication assets and named colors
```

Provider adapters are added under `Features/Authentication/Providers/`, one provider per file.

`ContentView.swift` delegates to `ApplicationRootView`. Existing WebView, StoreKit, CloudKit, photo, and migration services remain focused on their current responsibilities.

## 8. API Configuration

The iOS app reads the API base URL from an Info.plist value populated by build settings:

- Debug: local or staging URL
- Release: production HTTPS URL

The Release configuration must fail its release verification gate when the API URL is absent, non-HTTPS, or points to staging.

Provider client IDs, redirect schemes, and enablement flags are build configuration, not source-code constants. Secrets remain on the backend or in protected CI/App Store configuration.

## 9. Error Handling

- Decode the shared API error envelope into stable error codes.
- Show generic authentication failures for invalid credentials.
- Show rate-limit guidance using `Retry-After` without exposing internal details.
- Preserve field values after recoverable network errors, except passwords may be cleared when the request is rejected.
- Never log passwords, refresh tokens, access tokens, authorization codes, nonces, Passkey assertions, or recovery codes.
- All loading actions are idempotent from the user's perspective and disable duplicate submission.
- Cancellation of Apple, Google, Huawei, or Passkey authorization returns to the same screen without an error alert.

## 10. Accessibility and Adaptation

- Interactive controls have at least 44 × 44 pt tap targets.
- Text fields use appropriate content types and password privacy.
- VoiceOver labels identify each provider and distinguish login from sign-up.
- Keyboard submission advances fields and submits only when valid.
- The form scrolls above the keyboard on smaller supported iPhones.
- Dynamic Type preserves the design intent and allows scrolling rather than clipping.
- Error messages are announced to VoiceOver.
- Reduced-motion users receive no decorative transition requirement.

## 11. Testing and Acceptance

### Automated

- Go tests prove 7-character passwords fail, 8-character passwords pass unless weak, and existing Argon2id verification remains valid.
- OpenAPI contract tests prove the 8-character minimum.
- Swift unit tests cover Clovery ID normalization, password validation, confirmation mismatch, device registration encoding, API error mapping, token rotation, Keychain clearing, and legacy-route decisions.
- URLProtocol-backed client tests verify every request path and JSON field against the Go contract.
- View-model tests cover duplicate submission, cancellation, invalid credentials, unavailable provider, registration recovery codes, and revoked refresh sessions.
- Existing V1 bridge, StoreKit, CloudKit, photo, migration, and release-gate tests remain green.

### Simulator

- Compare the three screens at 402 × 874 against the Figma screenshots.
- Verify keyboard behavior on a smaller supported iPhone simulator.
- Verify fresh-install routing, legacy-upgrade routing, update-notice dismissal, and binding entry.
- Verify Dynamic Type and VoiceOver labels.

### Deferred Real Device

After native iOS implementation is complete and before Flutter work begins:

- Apple login
- Google login
- Huawei login where supported
- Passkey creation/login
- Keychain persistence across relaunch
- Existing-user upgrade with real local diary/photos
- TestFlight production-like API configuration

## 12. Release Gates

The authentication feature is not App Store-ready until:

- Production API hostname is deployed and HTTPS.
- Database migrations are backed up and restore-tested.
- Apple, Google, and Huawei provider configuration passes backend preflight.
- Sign in with Apple capability and App Store configuration match the production bundle ID.
- Password, refresh, provider, Passkey, recovery-code, legacy-upgrade, and logout acceptance tests pass.
- No existing-user diary or photo data is deleted when binding, cancelling, logging out, or encountering an API failure.
- Recovery codes are shown exactly once and are not retained in diagnostics.

