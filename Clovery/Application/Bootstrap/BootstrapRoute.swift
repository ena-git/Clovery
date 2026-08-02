import Foundation

enum BootstrapReconciliationState: Equatable {
    case working(AccountBootstrapStatus?)
    case retryable(String)
    case needsAttention(String)
}

enum BootstrapRoute: Equatable {
    case loading
    case upgradeNotice
    case authentication
    case reconciling(BootstrapReconciliationState)
    case diary(accountID: String, vaultID: String)
}
