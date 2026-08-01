#if DEBUG
import Foundation

@MainActor
struct IOSVerificationAccountDependencies {
    let api: AccountManagementAPIProtocol
    let session: AccountDeletionSessionEnding
    let entitlementCache: AccountEntitlementCacheClearing
    let entitlementState: AccountEntitlementStateResetting

    init() {
        api = IOSVerificationAccountAPI()
        session = IOSVerificationDeletionSession()
        entitlementCache = IOSVerificationEntitlementCache()
        entitlementState = IOSVerificationEntitlementState()
    }
}

@MainActor
private final class IOSVerificationAccountAPI: AccountManagementAPIProtocol {
    func summary() async throws -> AccountSummary {
        AccountSummary(
            cloveryID: "verification_user",
            status: .active,
            createdAt: Date(timeIntervalSince1970: 100),
            hasPassword: true,
            passkeyCount: 1,
            recoveryCodesRemaining: 8,
            bindings: [
                AccountBinding(provider: .apple),
                AccountBinding(provider: .google)
            ]
        )
    }

    func requestDeletion() async throws -> AccountDeletionRequest {
        AccountDeletionRequest(
            requestID: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
            status: .pending,
            requestedAt: Date(timeIntervalSince1970: 100),
            scheduledFor: Date(timeIntervalSince1970: 200)
        )
    }
}

@MainActor
private final class IOSVerificationDeletionSession: AccountDeletionSessionEnding {
    func logout() {}
}

@MainActor
private final class IOSVerificationEntitlementCache: AccountEntitlementCacheClearing {
    func clear() throws {}
}

@MainActor
private final class IOSVerificationEntitlementState: AccountEntitlementStateResetting {
    func resetAccountEntitlementState() {}
}
#endif
