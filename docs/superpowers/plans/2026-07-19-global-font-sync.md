# Clovery Global Font Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing font choice from Clovery settings drive every iOS Web, SwiftUI authentication, upgrade notice, and widget surface while surviving logout and app restart.

**Architecture:** Keep the Web setting `clovery_tweak.fontHand` as the user-facing control, bridge its existing `widget_font` payload into a new `AppFontStore`, and inject the published selection through SwiftUI Environment. Store the canonical value in the existing App Group, mirror the legacy widget key, and resolve all custom fonts through one defensive resolver.

**Tech Stack:** Swift 5, SwiftUI, UIKit font descriptors, WKWebView message bridge, App Group `UserDefaults`, WidgetKit, XCTest, Xcode 26.

---

## File Structure

### New production files

- `Clovery/Application/Appearance/AppFontSelection.swift`
  - Owns supported persisted identifiers and storage keys.
- `Clovery/Application/Appearance/AppFontStore.swift`
  - Loads, migrates, publishes, and persists the device font choice.
- `Clovery/Application/Appearance/CloveryFontModifier.swift`
  - Resolves custom fonts with fallbacks and exposes role-based SwiftUI modifiers.

### New test files

- `CloveryTests/TestSupport/AuthenticationAPISpy.swift`
  - Shared authentication API test double required by existing login and signup tests.
- `CloveryTests/AppFontSelectionTests.swift`
  - Validates stored identifier parsing.
- `CloveryTests/AppFontStoreTests.swift`
  - Validates migration, persistence, and invalid-value fallback.
- `CloveryTests/CloveryFontResolverTests.swift`
  - Validates bundled resources and system fallback.
- `CloveryTests/GlobalFontBridgeTests.swift`
  - Validates Web bridge updates the native store.
- `CloveryTests/GlobalFontPresentationContractTests.swift`
  - Validates all native auth and upgrade views use dynamic font roles.
- `CloveryTests/WidgetFontContractTests.swift`
  - Validates widget compatibility and all four mappings.

### Modified production files

- `Clovery.xcodeproj/project.pbxproj`
  - Adds the three new application source files and shares the font resource folder with the widget target.
- `Clovery/Info.plist`
  - Registers all bundled fonts needed by native SwiftUI.
- `Clovery/WebView.swift`
  - Passes font payloads to `AppFontStore`.
- `Clovery/Application/ApplicationRootView.swift`
  - Owns the store and injects the selected font.
- `Clovery/Features/Authentication/Presentation/AuthenticationTheme.swift`
  - Keeps colors only; removes fixed font definitions.
- Authentication presentation files and components
  - Replace fixed auth fonts with dynamic role modifiers.
- `Clovery/Features/Upgrade/UpgradeNoticeView.swift`
  - Uses dynamic role modifiers.
- `CloveryWidget/Info.plist`
  - Points widget font registrations at the shared `fonts` resource directory.
- `CloveryWidget/CloveryWidget.swift`
  - Reads the canonical key first and maps all four font selections.

---

### Task 0: Preserve the completed crash and Chinese UI fixes

**Files:**
- Modify: none
- Stage existing changes only:
  - `Clovery/CloudKitSync.swift`
  - `Clovery/CloveryApp.swift`
  - `Clovery/Features/Authentication/Presentation/AccountRecoveryView.swift`
  - `Clovery/Features/Authentication/Presentation/AuthenticationEntryView.swift`
  - `Clovery/Features/Authentication/Presentation/AuthenticationProviderViewModel.swift`
  - `Clovery/Features/Authentication/Presentation/Components/AuthDivider.swift`
  - `Clovery/Features/Authentication/Presentation/Components/AuthProviderButton.swift`
  - `Clovery/Features/Authentication/Presentation/LoginView.swift`
  - `Clovery/Features/Authentication/Presentation/RecoveryCodesView.swift`
  - `Clovery/Features/Authentication/Presentation/SignUpView.swift`
  - `Clovery/Features/Upgrade/UpgradeNoticeView.swift`

- [ ] **Step 1: Verify the pending changes are limited to the completed work**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only the listed crash and Chinese presentation files are modified.

- [ ] **Step 2: Rebuild the current application baseline**

Run:

```bash
xcodebuild -quiet build \
  -project Clovery.xcodeproj \
  -scheme Clovery \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=30206471-4620-4407-A86D-64FE7589A210' \
  -derivedDataPath /private/tmp/clovery-font-derived \
  CODE_SIGNING_ALLOWED=NO
```

Expected: exit code `0`.

- [ ] **Step 3: Commit only the completed baseline**

```bash
git add \
  Clovery/CloudKitSync.swift \
  Clovery/CloveryApp.swift \
  Clovery/Features/Authentication/Presentation/AccountRecoveryView.swift \
  Clovery/Features/Authentication/Presentation/AuthenticationEntryView.swift \
  Clovery/Features/Authentication/Presentation/AuthenticationProviderViewModel.swift \
  Clovery/Features/Authentication/Presentation/Components/AuthDivider.swift \
  Clovery/Features/Authentication/Presentation/Components/AuthProviderButton.swift \
  Clovery/Features/Authentication/Presentation/LoginView.swift \
  Clovery/Features/Authentication/Presentation/RecoveryCodesView.swift \
  Clovery/Features/Authentication/Presentation/SignUpView.swift \
  Clovery/Features/Upgrade/UpgradeNoticeView.swift
git commit -m "fix: stabilize simulator and localize authentication"
```

Expected: one commit containing no global-font implementation.

---

### Task 1: Restore the shared authentication test fixture

**Files:**
- Create: `CloveryTests/TestSupport/AuthenticationAPISpy.swift`
- Modify: `CloveryTests/SignUpViewModelTests.swift:56`
- Test: `CloveryTests/LoginViewModelTests.swift`
- Test: `CloveryTests/SignUpViewModelTests.swift`

- [ ] **Step 1: Create the shared test double**

Create `CloveryTests/TestSupport/AuthenticationAPISpy.swift`:

```swift
import Foundation
@testable import Clovery

@MainActor
final class AuthenticationAPISpy: AuthenticationAPIProtocol {
    var registerResponse = AuthSessionResponse(
        accountID: "account",
        vaultID: "vault",
        accessToken: "access",
        accessTokenExpiresIn: 900,
        refreshToken: "refresh",
        recoveryCodes: nil
    )
    var registerError: Error?
    var loginError: Error?
    var loginDelayNanoseconds: UInt64 = 0
    private(set) var registerCallCount = 0
    private(set) var loginCallCount = 0

    func register(
        loginID: String,
        password: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        return registerResponse
    }

    func login(
        loginID: String,
        password: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        loginCallCount += 1
        if loginDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: loginDelayNanoseconds)
        }
        if let loginError {
            throw loginError
        }
        return registerResponse
    }

    func refresh(refreshToken: String) async throws -> AuthSessionResponse {
        registerResponse
    }

    func startFederatedLogin(provider: IdentityProvider) async throws -> FederationIntentResponse {
        FederationIntentResponse(
            intentID: "intent",
            provider: provider.rawValue,
            nonce: "nonce",
            expiresIn: 300
        )
    }

    func completeFederatedLogin(
        provider: IdentityProvider,
        intentID: String,
        nonce: String,
        authorizationCode: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        registerResponse
    }

    func startPasskeyLogin() async throws -> PasskeyCeremonyResponse {
        PasskeyCeremonyResponse(
            challengeID: "challenge",
            options: [:],
            expiresIn: 300
        )
    }

    func completePasskeyLogin(
        challengeID: String,
        response: [String: JSONValue],
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        registerResponse
    }

    func consumeRecoveryCode(
        loginID: String,
        recoveryCode: String
    ) async throws -> RecoveryProofResponse {
        RecoveryProofResponse(
            resetIntentID: "reset-intent",
            recoveryProof: "reset-proof",
            expiresIn: 600
        )
    }

    func completePasswordReset(
        resetIntentID: String,
        proof: String,
        newPassword: String
    ) async throws {}
}
```

- [ ] **Step 2: Remove the file-private duplicate**

Delete lines `56-145` from `CloveryTests/SignUpViewModelTests.swift`, leaving only `SignUpViewModelTests`.

- [ ] **Step 3: Run the two previously blocked suites**

Run:

```bash
xcodebuild -quiet test \
  -project Clovery.xcodeproj \
  -scheme Clovery \
  -destination 'platform=iOS Simulator,id=30206471-4620-4407-A86D-64FE7589A210' \
  -derivedDataPath /private/tmp/clovery-font-derived \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:CloveryTests/LoginViewModelTests \
  -only-testing:CloveryTests/SignUpViewModelTests
```

Expected: both suites pass; no `AuthenticationAPISpy` scope error.

- [ ] **Step 4: Commit the test fixture repair**

```bash
git add CloveryTests/TestSupport/AuthenticationAPISpy.swift CloveryTests/SignUpViewModelTests.swift
git commit -m "test: share authentication api spy"
```

---

### Task 2: Add font selection and persistent store

**Files:**
- Create: `Clovery/Application/Appearance/AppFontSelection.swift`
- Create: `Clovery/Application/Appearance/AppFontStore.swift`
- Create: `CloveryTests/AppFontSelectionTests.swift`
- Create: `CloveryTests/AppFontStoreTests.swift`
- Modify: `Clovery.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing identifier tests**

Create `CloveryTests/AppFontSelectionTests.swift`:

```swift
import XCTest
@testable import Clovery

final class AppFontSelectionTests: XCTestCase {
    func testStoredIdentifiersMatchWebSettings() {
        XCTAssertEqual(AppFontSelection(storedValue: "Gaegu"), .handwriting)
        XCTAssertEqual(AppFontSelection(storedValue: "System"), .system)
        XCTAssertEqual(AppFontSelection(storedValue: "NotoSerifSC"), .notoSerifSC)
        XCTAssertEqual(AppFontSelection(storedValue: "NaiChaTi"), .naiChaTi)
    }

    func testMissingOrUnknownIdentifierFallsBackToHandwriting() {
        XCTAssertEqual(AppFontSelection(storedValue: nil), .handwriting)
        XCTAssertEqual(AppFontSelection(storedValue: "UnknownFont"), .handwriting)
    }
}
```

- [ ] **Step 2: Run the identifier tests and confirm failure**

Run:

```bash
xcodebuild -quiet test \
  -project Clovery.xcodeproj \
  -scheme Clovery \
  -destination 'platform=iOS Simulator,id=30206471-4620-4407-A86D-64FE7589A210' \
  -derivedDataPath /private/tmp/clovery-font-derived \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:CloveryTests/AppFontSelectionTests
```

Expected: FAIL because `AppFontSelection` does not exist.

- [ ] **Step 3: Implement the persisted identifier model**

Create `Clovery/Application/Appearance/AppFontSelection.swift`:

```swift
import Foundation

enum AppFontSelection: String, CaseIterable, Equatable {
    case handwriting = "Gaegu"
    case system = "System"
    case notoSerifSC = "NotoSerifSC"
    case naiChaTi = "NaiChaTi"

    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .handwriting
    }
}

enum AppFontStorageKey {
    static let selection = "clovery_font_selection"
    static let widgetCompatibility = "widget_font"
}
```

- [ ] **Step 4: Write failing migration and persistence tests**

Create `CloveryTests/AppFontStoreTests.swift`:

```swift
import XCTest
@testable import Clovery

@MainActor
final class AppFontStoreTests: XCTestCase {
    private var primaryDefaults: UserDefaults!
    private var fallbackDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        primaryDefaults = UserDefaults(suiteName: "AppFontStoreTests.primary.\(UUID())")!
        fallbackDefaults = UserDefaults(suiteName: "AppFontStoreTests.fallback.\(UUID())")!
    }

    func testLegacyWidgetValueMigratesToCanonicalKey() {
        primaryDefaults.set("NaiChaTi", forKey: AppFontStorageKey.widgetCompatibility)

        let store = AppFontStore(
            primaryDefaults: primaryDefaults,
            fallbackDefaults: fallbackDefaults
        )

        XCTAssertEqual(store.selection, .naiChaTi)
        XCTAssertEqual(
            primaryDefaults.string(forKey: AppFontStorageKey.selection),
            "NaiChaTi"
        )
    }

    func testUpdatePublishesAndMirrorsBothKeys() {
        let store = AppFontStore(
            primaryDefaults: primaryDefaults,
            fallbackDefaults: fallbackDefaults
        )

        store.update(rawValue: "System")

        XCTAssertEqual(store.selection, .system)
        XCTAssertEqual(primaryDefaults.string(forKey: AppFontStorageKey.selection), "System")
        XCTAssertEqual(
            primaryDefaults.string(forKey: AppFontStorageKey.widgetCompatibility),
            "System"
        )
    }

    func testUnknownValueResetsToSafeDefault() {
        let store = AppFontStore(
            primaryDefaults: primaryDefaults,
            fallbackDefaults: fallbackDefaults
        )

        store.update(rawValue: "RemovedFont")

        XCTAssertEqual(store.selection, .handwriting)
    }
}
```

- [ ] **Step 5: Run the store tests and confirm failure**

Run the same `xcodebuild test` command with:

```bash
-only-testing:CloveryTests/AppFontStoreTests
```

Expected: FAIL because `AppFontStore` does not exist.

- [ ] **Step 6: Implement the store**

Create `Clovery/Application/Appearance/AppFontStore.swift`:

```swift
import Combine
import Foundation

@MainActor
final class AppFontStore: ObservableObject {
    static let appGroupIdentifier = "group.com.clovery.app"

    @Published private(set) var selection: AppFontSelection

    private let primaryDefaults: UserDefaults?
    private let fallbackDefaults: UserDefaults

    init(
        primaryDefaults: UserDefaults? = UserDefaults(
            suiteName: AppFontStore.appGroupIdentifier
        ),
        fallbackDefaults: UserDefaults = .standard
    ) {
        self.primaryDefaults = primaryDefaults
        self.fallbackDefaults = fallbackDefaults

        let storedValue =
            primaryDefaults?.string(forKey: AppFontStorageKey.selection) ??
            primaryDefaults?.string(forKey: AppFontStorageKey.widgetCompatibility) ??
            fallbackDefaults.string(forKey: AppFontStorageKey.selection) ??
            fallbackDefaults.string(forKey: AppFontStorageKey.widgetCompatibility)

        selection = AppFontSelection(storedValue: storedValue)
        persist(selection)
    }

    func update(rawValue: String) {
        let resolved = AppFontSelection(storedValue: rawValue)
        if selection != resolved {
            selection = resolved
        }
        persist(resolved)
    }

    private func persist(_ selection: AppFontSelection) {
        for defaults in [primaryDefaults, fallbackDefaults].compactMap({ $0 }) {
            defaults.set(selection.rawValue, forKey: AppFontStorageKey.selection)
            defaults.set(selection.rawValue, forKey: AppFontStorageKey.widgetCompatibility)
        }
    }
}
```

- [ ] **Step 7: Register both new files in the application target**

Add these `PBXBuildFile` entries to `Clovery.xcodeproj/project.pbxproj`:

```text
AABB000000000000000000F0 /* AppFontSelection.swift in Sources */ = {isa = PBXBuildFile; fileRef = AABB000000000000000000F3 /* AppFontSelection.swift */; };
AABB000000000000000000F1 /* AppFontStore.swift in Sources */ = {isa = PBXBuildFile; fileRef = AABB000000000000000000F4 /* AppFontStore.swift */; };
```

Add these `PBXFileReference` entries:

```text
AABB000000000000000000F3 /* AppFontSelection.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Application/Appearance/AppFontSelection.swift; sourceTree = "<group>"; };
AABB000000000000000000F4 /* AppFontStore.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Application/Appearance/AppFontStore.swift; sourceTree = "<group>"; };
```

Add file references `F3` and `F4` to the `Clovery` PBX group and build files `F0` and `F1` to the application `Sources` phase.

- [ ] **Step 8: Run both font state suites**

Run:

```bash
xcodebuild -quiet test \
  -project Clovery.xcodeproj \
  -scheme Clovery \
  -destination 'platform=iOS Simulator,id=30206471-4620-4407-A86D-64FE7589A210' \
  -derivedDataPath /private/tmp/clovery-font-derived \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:CloveryTests/AppFontSelectionTests \
  -only-testing:CloveryTests/AppFontStoreTests
```

Expected: PASS.

- [ ] **Step 9: Commit font state**

```bash
git add \
  Clovery/Application/Appearance/AppFontSelection.swift \
  Clovery/Application/Appearance/AppFontStore.swift \
  CloveryTests/AppFontSelectionTests.swift \
  CloveryTests/AppFontStoreTests.swift \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat: persist global font selection"
```

---

### Task 3: Add defensive native font resolution

**Files:**
- Create: `Clovery/Application/Appearance/CloveryFontModifier.swift`
- Create: `CloveryTests/CloveryFontResolverTests.swift`
- Modify: `Clovery/Info.plist:25`
- Modify: `Clovery.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing resolver tests**

Create `CloveryTests/CloveryFontResolverTests.swift`:

```swift
import UIKit
import XCTest
@testable import Clovery

final class CloveryFontResolverTests: XCTestCase {
    func testNativeFontResourcesAreRegistered() {
        XCTAssertNotNil(UIFont(name: "YLHZYS", size: 16))
        XCTAssertNotNil(UIFont(name: "Yomogi-Regular", size: 16))
        XCTAssertNotNil(UIFont(name: "NotoSerifSC-ExtraLight", size: 16))
        XCTAssertNotNil(UIFont(name: "BoBoNaiChaTi", size: 16))
    }

    func testMissingCustomFontsFallBackToSystemFont() {
        let resolver = CloveryFontResolver(loadFont: { _, _ in nil })

        let resolved = resolver.uiFont(for: .naiChaTi, role: .body)

        XCTAssertEqual(resolved.familyName, UIFont.systemFont(ofSize: 24).familyName)
    }
}
```

- [ ] **Step 2: Run the resolver tests and confirm failure**

Run the focused `xcodebuild test` command with:

```bash
-only-testing:CloveryTests/CloveryFontResolverTests
```

Expected: FAIL because the resolver does not exist and the additional fonts are not registered.

- [ ] **Step 3: Register all native application fonts**

Extend `Clovery/Info.plist` `UIAppFonts`:

```xml
<array>
    <string>fonts/Gaegu-Regular.ttf</string>
    <string>fonts/Gaegu-Light.ttf</string>
    <string>fonts/Gaegu-Bold.ttf</string>
    <string>fonts/Yomogi-Regular.ttf</string>
    <string>fonts/YueLiangHai-ZiYouShu-2.ttf</string>
    <string>fonts/NotoSerifSC-VariableFont_wght.ttf</string>
    <string>fonts/NaiChaTi-2.ttf</string>
</array>
```

- [ ] **Step 4: Implement role-based font resolution**

Create `Clovery/Application/Appearance/CloveryFontModifier.swift`:

```swift
import SwiftUI
import UIKit

enum CloveryFontRole {
    case title
    case action
    case body
    case caption

    var pointSize: CGFloat {
        switch self {
        case .title: 48
        case .action, .body: 24
        case .caption: 16
        }
    }

    var textStyle: UIFont.TextStyle {
        switch self {
        case .title: .largeTitle
        case .action: .title3
        case .body: .body
        case .caption: .caption1
        }
    }
}

struct CloveryFontResolver {
    typealias FontLoader = (_ name: String, _ size: CGFloat) -> UIFont?

    private let loadFont: FontLoader

    init(loadFont: @escaping FontLoader = { UIFont(name: $0, size: $1) }) {
        self.loadFont = loadFont
    }

    func uiFont(
        for selection: AppFontSelection,
        role: CloveryFontRole
    ) -> UIFont {
        let baseFont: UIFont
        if selection == .system {
            baseFont = UIFont.systemFont(ofSize: role.pointSize)
        } else {
            baseFont = customFont(for: selection, size: role.pointSize) ??
                UIFont.systemFont(ofSize: role.pointSize)
        }
        return UIFontMetrics(forTextStyle: role.textStyle).scaledFont(for: baseFont)
    }

    private func customFont(
        for selection: AppFontSelection,
        size: CGFloat
    ) -> UIFont? {
        let fonts = postScriptNames(for: selection).compactMap {
            loadFont($0, size)
        }
        guard let primary = fonts.first else {
            return nil
        }
        guard fonts.count > 1 else {
            return primary
        }
        let descriptor = primary.fontDescriptor.addingAttributes([
            .cascadeList: fonts.dropFirst().map(\.fontDescriptor)
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    private func postScriptNames(
        for selection: AppFontSelection
    ) -> [String] {
        switch selection {
        case .handwriting:
            ["YLHZYS", "Gaegu-Regular", "Yomogi-Regular"]
        case .system:
            []
        case .notoSerifSC:
            ["NotoSerifSC-ExtraLight", "STSongti-SC-Regular"]
        case .naiChaTi:
            ["BoBoNaiChaTi", "YLHZYS", "Gaegu-Regular"]
        }
    }
}

private struct AppFontSelectionEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppFontSelection.handwriting
}

extension EnvironmentValues {
    var appFontSelection: AppFontSelection {
        get { self[AppFontSelectionEnvironmentKey.self] }
        set { self[AppFontSelectionEnvironmentKey.self] = newValue }
    }
}

private struct CloveryFontModifier: ViewModifier {
    @Environment(\.appFontSelection) private var selection
    let role: CloveryFontRole
    private let resolver = CloveryFontResolver()

    func body(content: Content) -> some View {
        content.font(Font(resolver.uiFont(for: selection, role: role)))
    }
}

extension View {
    func cloveryFont(_ role: CloveryFontRole) -> some View {
        modifier(CloveryFontModifier(role: role))
    }
}
```

- [ ] **Step 5: Register the modifier in the application target**

Add:

```text
AABB000000000000000000F2 /* CloveryFontModifier.swift in Sources */ = {isa = PBXBuildFile; fileRef = AABB000000000000000000F5 /* CloveryFontModifier.swift */; };
AABB000000000000000000F5 /* CloveryFontModifier.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Application/Appearance/CloveryFontModifier.swift; sourceTree = "<group>"; };
```

Add file reference `F5` to the `Clovery` PBX group and build file `F2` to the application `Sources` phase.

- [ ] **Step 6: Run resolver tests**

Run the focused `xcodebuild test` command for `CloveryFontResolverTests`.

Expected: PASS and all four bundled PostScript names resolve.

- [ ] **Step 7: Commit the resolver and resources**

```bash
git add \
  Clovery/Application/Appearance/CloveryFontModifier.swift \
  CloveryTests/CloveryFontResolverTests.swift \
  Clovery/Info.plist \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat: resolve native Clovery fonts"
```

---

### Task 4: Connect the Web setting to the native store

**Files:**
- Create: `CloveryTests/GlobalFontBridgeTests.swift`
- Modify: `Clovery/WebView.swift:10`
- Modify: `Clovery/WebView.swift:34`
- Modify: `Clovery/WebView.swift:509`
- Modify: `Clovery/WebView.swift:774`
- Modify: `Clovery/Application/ApplicationRootView.swift:3`

- [ ] **Step 1: Write the failing bridge test**

Create `CloveryTests/GlobalFontBridgeTests.swift`:

```swift
import XCTest
@testable import Clovery

@MainActor
final class GlobalFontBridgeTests: XCTestCase {
    func testWebFontPayloadUpdatesNativeFontStore() {
        let primary = UserDefaults(suiteName: "GlobalFontBridgeTests.\(UUID())")!
        let fallback = UserDefaults(suiteName: "GlobalFontBridgeTests.fallback.\(UUID())")!
        let store = AppFontStore(
            primaryDefaults: primary,
            fallbackDefaults: fallback
        )
        let coordinator = WebView.Coordinator(fontStore: store)

        coordinator.handleFontPreference("NotoSerifSC")

        XCTAssertEqual(store.selection, .notoSerifSC)
        XCTAssertEqual(
            primary.string(forKey: AppFontStorageKey.selection),
            "NotoSerifSC"
        )
    }
}
```

- [ ] **Step 2: Run the bridge test and confirm failure**

Run the focused test command for `GlobalFontBridgeTests`.

Expected: FAIL because `Coordinator` has no `fontStore` or `handleFontPreference`.

- [ ] **Step 3: Inject the store into WebView and Coordinator**

At the top of `WebView` add:

```swift
private let fontStore: AppFontStore?

init(fontStore: AppFontStore? = nil) {
    self.fontStore = fontStore
}
```

Extend `Coordinator`:

```swift
private let fontStore: AppFontStore?

init(
    photoStore: PhotoStoring = PhotoStore(),
    imageExporter: ImageExporting = ImageExportService(),
    fontStore: AppFontStore? = nil
) {
    self.photoStore = photoStore
    self.imageExporter = imageExporter
    self.fontStore = fontStore
    super.init()
}

@MainActor
func handleFontPreference(_ rawValue: String) {
    fontStore?.update(rawValue: rawValue)
}
```

Change coordinator creation:

```swift
func makeCoordinator() -> Coordinator {
    Coordinator(fontStore: fontStore)
}
```

- [ ] **Step 4: Apply the payload during existing App Group persistence**

Inside the existing `if let font = payload["widget_font"] as? String` block:

```swift
shared.set(font, forKey: AppFontStorageKey.widgetCompatibility)
Task { @MainActor [weak self] in
    self?.handleFontPreference(font)
}
```

Do not add a new Web message handler. Keep the existing Web `icloud` payload and widget refresh.

- [ ] **Step 5: Own and inject the store from ApplicationRootView**

Add:

```swift
@StateObject private var fontStore: AppFontStore
```

Add an initializer parameter:

```swift
fontStore: AppFontStore? = nil
```

Initialize it:

```swift
_fontStore = StateObject(wrappedValue: fontStore ?? AppFontStore())
```

Append the environment modifier after the existing `.sheet` modifier so both
the routed page and presented authentication sheet inherit the selection:

```swift
.environment(\.appFontSelection, fontStore.selection)
```

Pass the same store into the Web diary:

```swift
WebView(fontStore: fontStore)
    .ignoresSafeArea()
```

- [ ] **Step 6: Run bridge and store tests**

Run:

```bash
xcodebuild -quiet test \
  -project Clovery.xcodeproj \
  -scheme Clovery \
  -destination 'platform=iOS Simulator,id=30206471-4620-4407-A86D-64FE7589A210' \
  -derivedDataPath /private/tmp/clovery-font-derived \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:CloveryTests/AppFontStoreTests \
  -only-testing:CloveryTests/GlobalFontBridgeTests
```

Expected: PASS.

- [ ] **Step 7: Commit the bridge**

```bash
git add \
  Clovery/WebView.swift \
  Clovery/Application/ApplicationRootView.swift \
  CloveryTests/GlobalFontBridgeTests.swift
git commit -m "feat: bridge web font selection to SwiftUI"
```

---

### Task 5: Convert authentication and upgrade views to dynamic roles

**Files:**
- Create: `CloveryTests/GlobalFontPresentationContractTests.swift`
- Modify: `Clovery/Features/Authentication/Presentation/AuthenticationTheme.swift:11`
- Modify: `Clovery/Features/Authentication/Presentation/AuthenticationEntryView.swift`
- Modify: `Clovery/Features/Authentication/Presentation/LoginView.swift`
- Modify: `Clovery/Features/Authentication/Presentation/SignUpView.swift`
- Modify: `Clovery/Features/Authentication/Presentation/AccountRecoveryView.swift`
- Modify: `Clovery/Features/Authentication/Presentation/RecoveryCodesView.swift`
- Modify: `Clovery/Features/Authentication/Presentation/Components/AuthCapsuleField.swift`
- Modify: `Clovery/Features/Authentication/Presentation/Components/AuthDivider.swift`
- Modify: `Clovery/Features/Upgrade/UpgradeNoticeView.swift`

- [ ] **Step 1: Write the failing presentation contract**

Create `CloveryTests/GlobalFontPresentationContractTests.swift`:

```swift
import Foundation
import XCTest

final class GlobalFontPresentationContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testAuthenticationAndUpgradeViewsUseDynamicFontRoles() throws {
        let paths = [
            "Clovery/Features/Authentication/Presentation/AuthenticationEntryView.swift",
            "Clovery/Features/Authentication/Presentation/LoginView.swift",
            "Clovery/Features/Authentication/Presentation/SignUpView.swift",
            "Clovery/Features/Authentication/Presentation/AccountRecoveryView.swift",
            "Clovery/Features/Authentication/Presentation/RecoveryCodesView.swift",
            "Clovery/Features/Authentication/Presentation/Components/AuthCapsuleField.swift",
            "Clovery/Features/Authentication/Presentation/Components/AuthDivider.swift",
            "Clovery/Features/Upgrade/UpgradeNoticeView.swift",
        ]

        for path in paths {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            XCTAssertTrue(source.contains(".cloveryFont("), path)
            XCTAssertFalse(source.contains(".font(.auth"), path)
        }
    }

    func testFixedAuthenticationFontDefinitionsAreRemoved() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Clovery/Features/Authentication/Presentation/AuthenticationTheme.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("Gaegu-Regular"))
        XCTAssertFalse(source.contains("static let authTitle"))
    }
}
```

- [ ] **Step 2: Run the presentation contract and confirm failure**

Run the focused test command for `GlobalFontPresentationContractTests`.

Expected: FAIL because views still use `.font(.auth...)`.

- [ ] **Step 3: Replace every fixed auth font with a role**

Apply this exact mapping in all listed files:

```text
.font(.authTitle)   -> .cloveryFont(.title)
.font(.authAction)  -> .cloveryFont(.action)
.font(.authBody)    -> .cloveryFont(.body)
.font(.authCaption) -> .cloveryFont(.caption)
```

Delete the entire `extension Font` from `AuthenticationTheme.swift`, retaining the `Color` extension unchanged.

- [ ] **Step 4: Run the presentation and resolver tests**

Run:

```bash
xcodebuild -quiet test \
  -project Clovery.xcodeproj \
  -scheme Clovery \
  -destination 'platform=iOS Simulator,id=30206471-4620-4407-A86D-64FE7589A210' \
  -derivedDataPath /private/tmp/clovery-font-derived \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:CloveryTests/GlobalFontPresentationContractTests \
  -only-testing:CloveryTests/CloveryFontResolverTests
```

Expected: PASS.

- [ ] **Step 5: Commit native presentation integration**

```bash
git add \
  Clovery/Features/Authentication/Presentation/AuthenticationTheme.swift \
  Clovery/Features/Authentication/Presentation/AuthenticationEntryView.swift \
  Clovery/Features/Authentication/Presentation/LoginView.swift \
  Clovery/Features/Authentication/Presentation/SignUpView.swift \
  Clovery/Features/Authentication/Presentation/AccountRecoveryView.swift \
  Clovery/Features/Authentication/Presentation/RecoveryCodesView.swift \
  Clovery/Features/Authentication/Presentation/Components/AuthCapsuleField.swift \
  Clovery/Features/Authentication/Presentation/Components/AuthDivider.swift \
  Clovery/Features/Upgrade/UpgradeNoticeView.swift \
  CloveryTests/GlobalFontPresentationContractTests.swift
git commit -m "feat: apply global fonts to native screens"
```

---

### Task 6: Complete widget compatibility

**Files:**
- Create: `CloveryTests/WidgetFontContractTests.swift`
- Modify: `CloveryWidget/Info.plist:28`
- Modify: `CloveryWidget/CloveryWidget.swift:19`
- Modify: `Clovery.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write the failing widget contract**

Create `CloveryTests/WidgetFontContractTests.swift`:

```swift
import Foundation
import XCTest

final class WidgetFontContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testWidgetReadsCanonicalFontAndSupportsAllSelections() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "CloveryWidget/CloveryWidget.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("\"clovery_font_selection\""))
        XCTAssertTrue(source.contains("\"NotoSerifSC\""))
        XCTAssertTrue(source.contains("\"NaiChaTi\""))
        XCTAssertTrue(source.contains("\"NotoSerifSC-ExtraLight\""))
        XCTAssertTrue(source.contains("\"BoBoNaiChaTi\""))
    }
}
```

- [ ] **Step 2: Run the widget contract and confirm failure**

Run the focused test command for `WidgetFontContractTests`.

Expected: FAIL because the widget only reads `widget_font` and ignores the two Chinese custom fonts.

- [ ] **Step 3: Read the canonical key with compatibility fallback**

Change `CD.load()`:

```swift
let fontName =
    s?.string(forKey: "clovery_font_selection") ??
    s?.string(forKey: "widget_font") ??
    "Gaegu"
```

- [ ] **Step 4: Map all four font identifiers**

Replace `ps`, `psB`, and `isSys` with:

```swift
var ps: String {
    switch fontName {
    case "System":
        ""
    case "NotoSerifSC":
        "NotoSerifSC-ExtraLight"
    case "NaiChaTi":
        "BoBoNaiChaTi"
    default:
        lang == "zh" ? "YLHZYS" :
            lang == "ja" ? "Yomogi-Regular" : "Gaegu-Regular"
    }
}

var psB: String {
    switch fontName {
    case "System":
        ""
    case "NotoSerifSC":
        "NotoSerifSC-ExtraLight"
    case "NaiChaTi":
        "BoBoNaiChaTi"
    default:
        lang == "zh" ? "YLHZYS" :
            lang == "ja" ? "Yomogi-Regular" : "Gaegu-Bold"
    }
}

var isSys: Bool {
    fontName == "System"
}
```

- [ ] **Step 5: Register the shared font folder in the widget**

Update `CloveryWidget/Info.plist`:

```xml
<key>UIAppFonts</key>
<array>
    <string>fonts/Gaegu-Light.ttf</string>
    <string>fonts/Gaegu-Regular.ttf</string>
    <string>fonts/Gaegu-Bold.ttf</string>
    <string>fonts/Yomogi-Regular.ttf</string>
    <string>fonts/YueLiangHai-ZiYouShu-2.ttf</string>
    <string>fonts/NotoSerifSC-VariableFont_wght.ttf</string>
    <string>fonts/NaiChaTi-2.ttf</string>
</array>
```

Add a new widget `PBXBuildFile` for the existing font folder reference:

```text
FCECE0002FE92C7D0067AF51 /* fonts in Resources */ = {isa = PBXBuildFile; fileRef = AABB00000000000000000005 /* fonts */; };
```

Add it to `FCECDFDB2FE92C7C0067AF51 /* Resources */`.

- [ ] **Step 6: Run widget contract and build**

Run:

```bash
xcodebuild -quiet test \
  -project Clovery.xcodeproj \
  -scheme Clovery \
  -destination 'platform=iOS Simulator,id=30206471-4620-4407-A86D-64FE7589A210' \
  -derivedDataPath /private/tmp/clovery-font-derived \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  -only-testing:CloveryTests/WidgetFontContractTests

xcodebuild -quiet build \
  -project Clovery.xcodeproj \
  -scheme CloveryWidgetExtension \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=30206471-4620-4407-A86D-64FE7589A210' \
  -derivedDataPath /private/tmp/clovery-font-widget-derived \
  CODE_SIGNING_ALLOWED=NO
```

Expected: test and widget build both pass.

- [ ] **Step 7: Commit widget compatibility**

```bash
git add \
  CloveryWidget/Info.plist \
  CloveryWidget/CloveryWidget.swift \
  CloveryTests/WidgetFontContractTests.swift \
  Clovery.xcodeproj/project.pbxproj
git commit -m "feat: synchronize widget font selection"
```

---

### Task 7: Run release-focused verification

**Files:**
- Create: `docs/superpowers/evidence/2026-07-19-global-font-sync-verification.md`

- [ ] **Step 1: Run syntax and project validation**

Run:

```bash
plutil -lint Clovery/Info.plist CloveryWidget/Info.plist
git diff --check
xcodebuild -project Clovery.xcodeproj -scheme Clovery -list
```

Expected: both plists report `OK`, no diff errors, and the project lists the app and widget schemes.

- [ ] **Step 2: Run the full iOS unit test suite**

Run:

```bash
xcodebuild -quiet test \
  -project Clovery.xcodeproj \
  -scheme Clovery \
  -destination 'platform=iOS Simulator,id=30206471-4620-4407-A86D-64FE7589A210' \
  -derivedDataPath /private/tmp/clovery-font-derived \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO
```

Expected: exit code `0`; all `CloveryTests` pass.

- [ ] **Step 3: Build, install, and launch the application**

Run:

```bash
xcodebuild -quiet build \
  -project Clovery.xcodeproj \
  -scheme Clovery \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=30206471-4620-4407-A86D-64FE7589A210' \
  -derivedDataPath /private/tmp/clovery-font-derived \
  CODE_SIGNING_ALLOWED=NO

xcrun simctl install \
  30206471-4620-4407-A86D-64FE7589A210 \
  /private/tmp/clovery-font-derived/Build/Products/Debug-iphonesimulator/Clovery.app

xcrun simctl launch \
  30206471-4620-4407-A86D-64FE7589A210 \
  com.clovery.app
```

Expected: build succeeds and `simctl launch` returns a Clovery PID.

- [ ] **Step 4: Perform the four-font acceptance pass**

For each setting value `手写体`, `系统默认`, `雅宋`, and `奶茶体`:

1. Select the font in 设置 → 外观 → 字体.
2. Confirm the visible Web interface changes immediately.
3. Open the binding/login flow and confirm the Chinese login UI uses the same family.
4. Navigate through registration and account recovery.
5. Show the old-user upgrade notice and confirm its family matches.
6. Exit and relaunch Clovery; confirm the selection persists.
7. Confirm no new `Clovery-*.ips` report appears in `~/Library/Logs/DiagnosticReports`.

Expected: all seven checks pass for all four font values.

- [ ] **Step 5: Record evidence**

Create `docs/superpowers/evidence/2026-07-19-global-font-sync-verification.md` containing:

```markdown
# Global Font Sync Verification

- App build: PASS
- Widget build: PASS
- Full XCTest suite: PASS
- Handwriting: Web / auth / upgrade / relaunch PASS
- System: Web / auth / upgrade / relaunch PASS
- Noto Serif SC: Web / auth / upgrade / relaunch PASS
- NaiChaTi: Web / auth / upgrade / relaunch PASS
- New startup crash reports: NONE
```

- [ ] **Step 6: Commit verification evidence**

```bash
git add docs/superpowers/evidence/2026-07-19-global-font-sync-verification.md
git commit -m "docs: verify global font synchronization"
```

- [ ] **Step 7: Confirm clean branch state**

Run:

```bash
git status --short
git log --oneline -8
```

Expected: clean working tree and separate commits for baseline, test fixture, font state, resolver, bridge, presentations, widget, and evidence.
