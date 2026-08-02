import Foundation

enum AccountBootstrapPipelineError: Error, Equatable {
    case retryable(String)
    case needsAttention(String)
}

@MainActor
protocol BootstrapMigrationRunning: AnyObject {
    func run(accountID: String, vaultID: String) async throws -> LegacyMigrationOutcome
}

@MainActor
protocol BootstrapEntitlementReconciling: AnyObject {
    func reconcileForBootstrap(
        accountID: String
    ) async -> EntitlementReconciliationOutcome
}

@MainActor
protocol AccountBootstrapPipelining: AnyObject {
    func run(
        initialStatus: AccountBootstrapStatus,
        session: AuthenticationSession,
        sourceKind: BootstrapSourceKind,
        progress: (AccountBootstrapStatus) -> Void
    ) async throws -> AccountBootstrapStatus
}

@MainActor
final class AccountBootstrapPipeline: AccountBootstrapPipelining {
    private let api: AccountBootstrapAPIProtocol
    private let migration: BootstrapMigrationRunning
    private let entitlement: BootstrapEntitlementReconciling
    private let vaultPuller: InitialVaultPulling

    init(
        api: AccountBootstrapAPIProtocol,
        migration: BootstrapMigrationRunning,
        entitlement: BootstrapEntitlementReconciling,
        vaultPuller: InitialVaultPulling
    ) {
        self.api = api
        self.migration = migration
        self.entitlement = entitlement
        self.vaultPuller = vaultPuller
    }

    func run(
        initialStatus: AccountBootstrapStatus,
        session: AuthenticationSession,
        sourceKind: BootstrapSourceKind,
        progress: (AccountBootstrapStatus) -> Void
    ) async throws -> AccountBootstrapStatus {
        var status = initialStatus
        for _ in 0..<8 {
            try Task.checkCancellation()
            progress(status)
            switch status.overall {
            case .complete:
                return status
            case let .needsAttention(code):
                throw AccountBootstrapPipelineError.needsAttention(code)
            case .pending, .running:
                break
            }

            if status.stages.migration != .complete {
                if sourceKind == .legacyLocal {
                    switch try await migration.run(
                        accountID: session.accountID,
                        vaultID: session.vaultID
                    ) {
                    case .verified:
                        status = try await api.status()
                    case let .needsAttention(code):
                        throw AccountBootstrapPipelineError.needsAttention(code)
                    }
                } else {
                    status = try await api.resume(
                        sourceKind: sourceKind,
                        vaultCheckpoint: nil
                    )
                }
                continue
            }

            if status.stages.entitlement != .complete {
                switch await entitlement.reconcileForBootstrap(accountID: session.accountID) {
                case .complete:
                    status = try await api.status()
                case .pending:
                    throw AccountBootstrapPipelineError.retryable(
                        "entitlement_temporarily_unavailable"
                    )
                case let .needsAttention(code):
                    throw AccountBootstrapPipelineError.needsAttention(code)
                }
                continue
            }

            if status.stages.vault != .complete {
                let result = try await vaultPuller.pull(
                    namespace: VaultSyncNamespace(
                        accountID: session.accountID,
                        vaultID: session.vaultID
                    ),
                    migrationID: status.migrationID,
                    sourceKind: sourceKind
                )
                status = result.status
                continue
            }

            status = try await api.status()
        }
        throw AccountBootstrapPipelineError.retryable("bootstrap_no_progress")
    }
}

extension LegacyMigrationCoordinator: BootstrapMigrationRunning {}
extension BoardStore: BootstrapEntitlementReconciling {}
