#if DEBUG
import Foundation
import SwiftUI

enum IOSVerificationFixture: String, CaseIterable {
    case authentication
    case notice
    case providerLogin = "provider-login"
    case identityClaim = "identity-claim"
    case migration
    case entitlement
    case needsAttention = "needs-attention"
    case diary
    case accountSecurity = "account-security"

    static func resolve(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
        argumentValue(for: "-CloveryVerificationFixture", in: arguments).flatMap(Self.init)
    }

    static func fontSelection(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> AppFontSelection {
        AppFontSelection(
            storedValue: argumentValue(for: "-CloveryVerificationFont", in: arguments)
        )
    }

    static func dynamicTypeSize(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> DynamicTypeSize {
        argumentValue(for: "-CloveryVerificationDynamicType", in: arguments) == "accessibility"
            ? .accessibility5
            : .large
    }

    static func reduceMotion(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        argumentValue(for: "-CloveryVerificationReduceMotion", in: arguments) == "true"
    }

    private static func argumentValue(for key: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

@MainActor
struct IOSVerificationFixtureView: View {
    let fixture: IOSVerificationFixture

    private let authenticationAPI: AuthenticationAPIProtocol
    private let identityClaimAPI: IdentityClaimAPIProtocol
    private let vaultRegistry: AccountVaultRuntimeRegistry
    private let verificationAccount: IOSVerificationAccountDependencies
    private let dynamicTypeSize: DynamicTypeSize
    private let reduceMotion: Bool
    @StateObject private var sessionController: ApplicationSessionController
    @StateObject private var boardStore: BoardStore
    @StateObject private var fontStore: AppFontStore

    init(
        fixture: IOSVerificationFixture,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.fixture = fixture
        let dependencies = BootstrapDependencies.live()
        authenticationAPI = dependencies.authenticationAPI
        identityClaimAPI = dependencies.identityClaimAPI
        vaultRegistry = dependencies.vaultRegistry
        verificationAccount = IOSVerificationAccountDependencies()
        dynamicTypeSize = IOSVerificationFixture.dynamicTypeSize(arguments: arguments)
        reduceMotion = IOSVerificationFixture.reduceMotion(arguments: arguments)
        _sessionController = StateObject(wrappedValue: dependencies.sessionController)
        _boardStore = StateObject(wrappedValue: dependencies.boardStore)

        let defaults = UserDefaults(suiteName: "com.clovery.verification.font") ?? .standard
        let fontStore = AppFontStore(primaryDefaults: defaults, fallbackDefaults: defaults)
        fontStore.update(rawValue: IOSVerificationFixture.fontSelection(arguments: arguments).rawValue)
        _fontStore = StateObject(wrappedValue: fontStore)
    }

    var body: some View {
        fixtureView
            .environment(\.appFontSelection, fontStore.selection)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
    }

    @ViewBuilder
    private var fixtureView: some View {
        switch fixture {
        case .authentication:
            NavigationStack {
                AuthenticationEntryView(showLogin: {}, showSignUp: {})
            }
            .tint(.authInk)
        case .notice:
            ZStack {
                ApplicationLoadingView(showsTitle: false)
                    .accessibilityHidden(true)
                UpgradeNoticeView(acknowledge: {})
            }
        case .providerLogin:
            NavigationStack {
                LoginView(
                    api: authenticationAPI,
                    sessionController: sessionController,
                    showSignUp: {},
                    quickProviders: [.apple, .google]
                )
            }
            .tint(.authInk)
        case .identityClaim:
            NavigationStack {
                IdentityClaimRegistrationView(
                    api: identityClaimAPI,
                    sessionHandler: sessionController,
                    claim: IdentityClaimContext(
                        provider: .apple,
                        token: "debug-verification-only",
                        expiresAt: .distantFuture
                    ),
                    sourceKind: .legacyLocal,
                    reauthorize: { _ in }
                )
            }
            .tint(.authInk)
        case .migration:
            AccountReconciliationView(
                state: .working(status(activeStage: .migration)),
                retry: {},
                logout: {},
                reduceMotionOverride: reduceMotion
            )
        case .entitlement:
            AccountReconciliationView(
                state: .working(status(activeStage: .entitlement)),
                retry: {},
                logout: {},
                reduceMotionOverride: reduceMotion
            )
        case .needsAttention:
            IOSVerificationRetryRecoveryView(
                reduceMotion: reduceMotion
            )
        case .diary:
            let namespace = VaultSyncNamespace(
                accountID: "11111111-1111-4111-8111-111111111111",
                vaultID: "22222222-2222-4222-8222-222222222222"
            )
            WebView(
                boardStore: boardStore,
                fontStore: fontStore,
                vaultContext: vaultRegistry.context(for: namespace)
            )
            .id(namespace.storageKey)
            .ignoresSafeArea()
        case .accountSecurity:
            AccountSecurityView(
                api: verificationAccount.api,
                session: verificationAccount.session,
                entitlementCache: verificationAccount.entitlementCache,
                entitlementState: verificationAccount.entitlementState
            )
        }
    }

    private func status(activeStage: VerificationBootstrapStage) -> AccountBootstrapStatus {
        AccountBootstrapStatus(
            overall: .running,
            sourceKind: .legacyLocal,
            migrationID: nil,
            stages: AccountBootstrapStages(
                identity: .complete,
                migration: activeStage == .migration ? .pending : .complete,
                entitlement: .pending,
                vault: .pending
            ),
            lastErrorCode: nil,
            retryCount: 0,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

private enum VerificationBootstrapStage {
    case migration
    case entitlement
}

@MainActor
private struct IOSVerificationRetryRecoveryView: View {
    let reduceMotion: Bool

    @State private var recovered = false

    var body: some View {
        AccountReconciliationView(
            state: recovered ? .working(nil) : .needsAttention("verification_offline"),
            retry: { recovered = true },
            logout: {},
            reduceMotionOverride: reduceMotion
        )
    }
}
#endif
