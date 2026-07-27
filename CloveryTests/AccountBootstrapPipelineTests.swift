import Foundation
import XCTest
@testable import Clovery

@MainActor
final class AccountBootstrapPipelineTests: XCTestCase {
    func testLegacyPipelineRunsMigrationEntitlementAndVaultInOrder() async throws {
        let calls = PipelineCalls()
        let migrationID = UUID()
        let api = PipelineBootstrapAPISpy(
            statuses: [
                status(migration: .complete, entitlement: .pending, vault: .pending, migrationID: migrationID),
                status(migration: .complete, entitlement: .complete, vault: .pending, migrationID: migrationID)
            ],
            calls: calls
        )
        let migration = PipelineMigrationSpy(calls: calls)
        let entitlement = PipelineEntitlementSpy(calls: calls, outcome: .complete([]))
        let finalStatus = status(
            overall: .complete,
            migration: .complete,
            entitlement: .complete,
            vault: .complete,
            migrationID: migrationID
        )
        let vault = PipelineVaultPullerSpy(calls: calls, result: .init(
            checkpoint: VaultCheckpoint(cursor: 9, hasMore: false),
            status: finalStatus
        ))
        let pipeline = AccountBootstrapPipeline(
            api: api,
            migration: migration,
            entitlement: entitlement,
            vaultPuller: vault
        )

        let result = try await pipeline.run(
            initialStatus: status(
                migration: .pending,
                entitlement: .pending,
                vault: .pending
            ),
            session: Self.session,
            sourceKind: .legacyLocal,
            progress: { _ in }
        )

        XCTAssertEqual(result, finalStatus)
        XCTAssertEqual(calls.values, ["migration", "status", "entitlement", "status", "vault"])
        XCTAssertEqual(vault.migrationIDs, [migrationID])
    }

    func testRestartSkipsAlreadyCompleteStages() async throws {
        let calls = PipelineCalls()
        let finalStatus = status(
            overall: .complete,
            migration: .complete,
            entitlement: .complete,
            vault: .complete
        )
        let pipeline = AccountBootstrapPipeline(
            api: PipelineBootstrapAPISpy(statuses: [], calls: calls),
            migration: PipelineMigrationSpy(calls: calls),
            entitlement: PipelineEntitlementSpy(calls: calls, outcome: .complete([])),
            vaultPuller: PipelineVaultPullerSpy(
                calls: calls,
                result: .init(
                    checkpoint: VaultCheckpoint(cursor: 0, hasMore: false),
                    status: finalStatus
                )
            )
        )

        _ = try await pipeline.run(
            initialStatus: status(
                migration: .complete,
                entitlement: .complete,
                vault: .pending
            ),
            session: Self.session,
            sourceKind: .legacyLocal,
            progress: { _ in }
        )

        XCTAssertEqual(calls.values, ["vault"])
    }

    func testPendingEntitlementReturnsRetryableWithoutPullingVault() async {
        let calls = PipelineCalls()
        let pipeline = AccountBootstrapPipeline(
            api: PipelineBootstrapAPISpy(statuses: [], calls: calls),
            migration: PipelineMigrationSpy(calls: calls),
            entitlement: PipelineEntitlementSpy(calls: calls, outcome: .pending(cached: [])),
            vaultPuller: PipelineVaultPullerSpy(
                calls: calls,
                result: .init(
                    checkpoint: VaultCheckpoint(cursor: 0, hasMore: false),
                    status: status(overall: .complete, migration: .complete, entitlement: .complete, vault: .complete)
                )
            )
        )

        do {
            _ = try await pipeline.run(
                initialStatus: status(
                    migration: .complete,
                    entitlement: .pending,
                    vault: .pending
                ),
                session: Self.session,
                sourceKind: .newInstall,
                progress: { _ in }
            )
            XCTFail("Expected retryable pipeline failure.")
        } catch {
            XCTAssertEqual(
                error as? AccountBootstrapPipelineError,
                .retryable("entitlement_temporarily_unavailable")
            )
        }
        XCTAssertEqual(calls.values, ["entitlement"])
    }

    private static let session = AuthenticationSession(
        accountID: "11111111-1111-4111-8111-111111111111",
        vaultID: "22222222-2222-4222-8222-222222222222",
        accessToken: "access",
        accessTokenExpiresAt: Date().addingTimeInterval(900)
    )
}

@MainActor
private final class PipelineCalls {
    var values: [String] = []
}

@MainActor
private final class PipelineBootstrapAPISpy: AccountBootstrapAPIProtocol {
    private var statuses: [AccountBootstrapStatus]
    private let calls: PipelineCalls

    init(statuses: [AccountBootstrapStatus], calls: PipelineCalls) {
        self.statuses = statuses
        self.calls = calls
    }

    func status() async throws -> AccountBootstrapStatus {
        calls.values.append("status")
        return statuses.removeFirst()
    }

    func resume(
        sourceKind: BootstrapSourceKind,
        vaultCheckpoint: VaultCheckpoint?
    ) async throws -> AccountBootstrapStatus {
        calls.values.append("resume")
        return statuses.removeFirst()
    }
}

@MainActor
private final class PipelineMigrationSpy: BootstrapMigrationRunning {
    private let calls: PipelineCalls

    init(calls: PipelineCalls) { self.calls = calls }

    func run(accountID: String, vaultID: String) async throws -> LegacyMigrationOutcome {
        calls.values.append("migration")
        return .verified(LegacyMigrationReport(
            migrationID: UUID(),
            status: .verified,
            expectedEntries: 0,
            importedEntries: 0,
            insertedEntries: 0,
            duplicateEntries: 0,
            conflictCopies: 0,
            expectedDeletedEntries: 0,
            importedDeletedEntries: 0,
            expectedAssets: 0,
            verifiedAssets: 0,
            expectedBytes: 0,
            verifiedBytes: 0,
            verifiedAt: Date()
        ))
    }
}

@MainActor
private final class PipelineEntitlementSpy: BootstrapEntitlementReconciling {
    private let calls: PipelineCalls
    private let outcome: EntitlementReconciliationOutcome

    init(calls: PipelineCalls, outcome: EntitlementReconciliationOutcome) {
        self.calls = calls
        self.outcome = outcome
    }

    func reconcileForBootstrap(accountID: String) async -> EntitlementReconciliationOutcome {
        calls.values.append("entitlement")
        return outcome
    }
}

@MainActor
private final class PipelineVaultPullerSpy: InitialVaultPulling {
    private let calls: PipelineCalls
    private let result: InitialVaultPullResult
    private(set) var migrationIDs: [UUID?] = []

    init(calls: PipelineCalls, result: InitialVaultPullResult) {
        self.calls = calls
        self.result = result
    }

    func pull(
        namespace: VaultSyncNamespace,
        migrationID: UUID?,
        sourceKind: BootstrapSourceKind
    ) async throws -> InitialVaultPullResult {
        calls.values.append("vault")
        migrationIDs.append(migrationID)
        return result
    }
}

private func status(
    overall: AccountBootstrapOverallState = .running,
    migration: AccountBootstrapStageState,
    entitlement: AccountBootstrapStageState,
    vault: AccountBootstrapStageState,
    migrationID: UUID? = nil
) -> AccountBootstrapStatus {
    AccountBootstrapStatus(
        overall: overall,
        sourceKind: .legacyLocal,
        migrationID: migrationID,
        stages: AccountBootstrapStages(
            identity: .complete,
            migration: migration,
            entitlement: entitlement,
            vault: vault
        ),
        lastErrorCode: nil,
        retryCount: 0,
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}
