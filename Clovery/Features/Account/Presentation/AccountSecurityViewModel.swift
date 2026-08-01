import Combine
import Foundation

@MainActor
protocol AccountDeletionSessionEnding: AnyObject {
    func logout()
}

@MainActor
protocol AccountEntitlementCacheClearing: AnyObject {
    func clear() throws
}

@MainActor
protocol AccountEntitlementStateResetting: AnyObject {
    func resetAccountEntitlementState()
}

extension ApplicationSessionController: AccountDeletionSessionEnding {}
extension AccountEntitlementCache: AccountEntitlementCacheClearing {}

extension BoardStore: AccountEntitlementStateResetting {
    func resetAccountEntitlementState() {
        accountDidChange()
    }
}

@MainActor
final class AccountSecurityViewModel: ObservableObject {
    @Published private(set) var summary: AccountSummary?
    @Published private(set) var isLoading = false
    @Published private(set) var isDeleting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var cleanupWarning: String?
    @Published private(set) var didAcceptDeletion = false

    private let api: AccountManagementAPIProtocol
    private let session: AccountDeletionSessionEnding
    private let entitlementCache: AccountEntitlementCacheClearing
    private let entitlementState: AccountEntitlementStateResetting

    init(
        api: AccountManagementAPIProtocol,
        session: AccountDeletionSessionEnding,
        entitlementCache: AccountEntitlementCacheClearing,
        entitlementState: AccountEntitlementStateResetting
    ) {
        self.api = api
        self.session = session
        self.entitlementCache = entitlementCache
        self.entitlementState = entitlementState
    }

    var cloveryID: String? {
        summary?.cloveryID
    }

    var providerNames: [String] {
        summary?.bindings.map(\.provider.displayName) ?? []
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        summary = nil
        errorMessage = nil
        defer { isLoading = false }

        do {
            summary = try await api.summary()
        } catch {
            errorMessage = "账户信息加载失败，请检查网络后重试"
        }
    }

    func canConfirmDeletion(_ confirmation: String) -> Bool {
        guard let cloveryID else { return false }
        return confirmation == cloveryID
    }

    func requestDeletion(confirmation: String) async {
        guard !isDeleting, !didAcceptDeletion else { return }
        errorMessage = nil
        cleanupWarning = nil

        guard canConfirmDeletion(confirmation) else {
            errorMessage = "请输入完整 Clovery ID 以确认删除"
            return
        }

        isDeleting = true
        defer { isDeleting = false }

        do {
            _ = try await api.requestDeletion()
            do {
                try entitlementCache.clear()
            } catch {
                cleanupWarning = "账户已进入删除流程，但本地权益缓存清理未完成"
            }
            entitlementState.resetAccountEntitlementState()
            session.logout()
            didAcceptDeletion = true
        } catch {
            errorMessage = "账户删除请求失败，请检查网络后重试"
        }
    }
}

private extension AccountIdentityProvider {
    var displayName: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .huawei: "华为"
        case .wechat: "微信"
        case .qq: "QQ"
        }
    }
}
