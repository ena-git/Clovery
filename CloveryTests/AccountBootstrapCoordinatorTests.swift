import Foundation
import XCTest
@testable import Clovery

@MainActor
final class AccountBootstrapCoordinatorTests: XCTestCase {
    func testLegacyNoticeAppearsBeforeSessionRestoreThenAcknowledgementRoutesToAuthentication() async {
        let fixture = makeFixture(hasLegacyData: true, noticeAcknowledged: false)

        fixture.coordinator.start()

        XCTAssertEqual(fixture.coordinator.route, .upgradeNotice)
        XCTAssertEqual(fixture.session.restoreCalls, 0)

        fixture.coordinator.acknowledgeNotice()
        await fixture.coordinator.waitForIdle()

        XCTAssertEqual(fixture.notice.acknowledgeCalls, 1)
        XCTAssertEqual(fixture.session.restoreCalls, 1)
        XCTAssertEqual(fixture.coordinator.route, .authentication)
    }

    func testNewInstallWithoutSessionRoutesToAuthentication() async {
        let fixture = makeFixture()

        fixture.coordinator.start()
        await fixture.coordinator.waitForIdle()

        XCTAssertEqual(fixture.coordinator.route, .authentication)
    }

    func testValidSessionNeverEntersDiaryWhileBootstrapIsPending() async {
        let fixture = makeFixture(
            session: Self.session,
            statuses: [Self.pendingStatus, Self.pendingStatus]
        )

        fixture.coordinator.start()
        await fixture.coordinator.waitForIdle()

        guard case .reconciling = fixture.coordinator.route else {
            return XCTFail("pending bootstrap must stay gated")
        }
        XCTAssertEqual(fixture.api.resumeCalls, 1)
    }

    func testCompleteBootstrapEntersDiaryForCurrentAccountAndVault() async {
        let fixture = makeFixture(session: Self.session, statuses: [Self.completeStatus])

        fixture.coordinator.start()
        await fixture.coordinator.waitForIdle()

        XCTAssertEqual(
            fixture.coordinator.route,
            .diary(accountID: "account", vaultID: "vault")
        )
    }

    func testNeedsAttentionRemainsGatedWithStableCode() async {
        let fixture = makeFixture(session: Self.session, statuses: [Self.attentionStatus])

        fixture.coordinator.start()
        await fixture.coordinator.waitForIdle()

        XCTAssertEqual(
            fixture.coordinator.route,
            .reconciling(.needsAttention("purchase_chain_conflict"))
        )
    }

    func testLogoutCancelsWorkAndReturnsToAuthenticationWithoutClearingCheckpoint() async {
        let fixture = makeFixture(
            session: Self.session,
            statuses: [Self.pendingStatus],
            responseDelayNanoseconds: 200_000_000
        )
        fixture.coordinator.start()
        fixture.coordinator.logout()
        await fixture.coordinator.waitForIdle()

        XCTAssertEqual(fixture.coordinator.route, .authentication)
        XCTAssertEqual(fixture.session.logoutCalls, 1)
        XCTAssertEqual(fixture.checkpoint.clearCalls, 0)
    }

    func testRestartResumesStoredAccountBootstrapJob() async throws {
        let checkpoint = BootstrapCheckpoint(
            accountID: "account",
            vaultID: "vault",
            sourceKind: .legacyLocal,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let fixture = makeFixture(session: Self.session, statuses: [Self.pendingStatus, Self.pendingStatus])
        fixture.checkpoint.stored = checkpoint

        fixture.coordinator.start()
        await fixture.coordinator.waitForIdle()

        XCTAssertEqual(fixture.api.statusCalls, 1)
        XCTAssertEqual(fixture.api.resumeSourceKinds, [.legacyLocal])
        XCTAssertEqual(try fixture.checkpoint.load(), checkpoint)
    }

    func testStaleCompletionCannotOverrideNewAccountRoute() async {
        let fixture = makeFixture(
            session: Self.session,
            statuses: [Self.pendingStatus, Self.completeStatus],
            responseDelayNanoseconds: 100_000_000,
            ignoresCancellation: true
        )
        fixture.coordinator.start()
        try? await Task.sleep(nanoseconds: 10_000_000)
        fixture.session.session = AuthenticationSession(
            accountID: "second-account",
            vaultID: "second-vault",
            accessToken: "second-access",
            accessTokenExpiresAt: Date().addingTimeInterval(900)
        )
        fixture.coordinator.sessionDidChange()
        await fixture.coordinator.waitForIdle()

        XCTAssertEqual(
            fixture.coordinator.route,
            .diary(accountID: "second-account", vaultID: "second-vault")
        )
    }

    func testDifferentAccountCannotClaimStoredLegacyCheckpoint() async {
        let fixture = makeFixture(
            hasLegacyData: true,
            session: AuthenticationSession(
                accountID: "second-account",
                vaultID: "second-vault",
                accessToken: "access",
                accessTokenExpiresAt: Date().addingTimeInterval(900)
            ),
            statuses: [Self.completeStatus]
        )
        fixture.checkpoint.stored = BootstrapCheckpoint(
            accountID: "first-account",
            vaultID: "first-vault",
            sourceKind: .legacyLocal,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        fixture.coordinator.start()
        await fixture.coordinator.waitForIdle()

        XCTAssertEqual(
            fixture.coordinator.route,
            .reconciling(.needsAttention("bootstrap_account_mismatch"))
        )
        XCTAssertEqual(fixture.api.statusCalls, 0)
    }

    func testConfiguredPipelineMustCompleteBeforeDiaryRoute() async {
        let pipeline = AccountBootstrapPipelineSpy(result: Self.completeStatus)
        let fixture = makeFixture(
            session: Self.session,
            statuses: [Self.pendingStatus],
            pipeline: pipeline
        )

        fixture.coordinator.start()
        await fixture.coordinator.waitForIdle()

        XCTAssertEqual(pipeline.calls, 1)
        XCTAssertEqual(
            fixture.coordinator.route,
            .diary(accountID: "account", vaultID: "vault")
        )
    }

    private func makeFixture(
        hasLegacyData: Bool = false,
        noticeAcknowledged: Bool = true,
        session: AuthenticationSession? = nil,
        statuses: [AccountBootstrapStatus] = [],
        responseDelayNanoseconds: UInt64 = 0,
        ignoresCancellation: Bool = false,
        pipeline: AccountBootstrapPipelining? = nil
    ) -> CoordinatorFixture {
        let sessionController = BootstrapSessionSpy(session: session)
        let notice = BootstrapNoticeSpy(
            hasLegacyData: hasLegacyData,
            hasAcknowledgedNotice: noticeAcknowledged
        )
        let api = AccountBootstrapAPISpy(
            statuses: statuses,
            responseDelayNanoseconds: responseDelayNanoseconds,
            ignoresCancellation: ignoresCancellation
        )
        let checkpoint = BootstrapCheckpointStoreSpy()
        let coordinator = AccountBootstrapCoordinator(
            sessionController: sessionController,
            noticeController: notice,
            api: api,
            checkpointStore: checkpoint,
            pipeline: pipeline
        )
        return CoordinatorFixture(
            coordinator: coordinator,
            session: sessionController,
            notice: notice,
            api: api,
            checkpoint: checkpoint
        )
    }

    private static let session = AuthenticationSession(
        accountID: "account",
        vaultID: "vault",
        accessToken: "access",
        accessTokenExpiresAt: Date().addingTimeInterval(900)
    )
    private static let stages = AccountBootstrapStages(
        identity: .complete,
        migration: .pending,
        entitlement: .pending,
        vault: .pending
    )
    private static let pendingStatus = AccountBootstrapStatus(
        overall: .running,
        sourceKind: .legacyLocal,
        migrationID: nil,
        stages: stages,
        lastErrorCode: nil,
        retryCount: 0,
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    private static let completeStatus = AccountBootstrapStatus(
        overall: .complete,
        sourceKind: .newInstall,
        migrationID: nil,
        stages: AccountBootstrapStages(
            identity: .complete,
            migration: .complete,
            entitlement: .complete,
            vault: .complete
        ),
        lastErrorCode: nil,
        retryCount: 0,
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    private static let attentionStatus = AccountBootstrapStatus(
        overall: .needsAttention("purchase_chain_conflict"),
        sourceKind: .legacyLocal,
        migrationID: nil,
        stages: stages,
        lastErrorCode: "purchase_chain_conflict",
        retryCount: 1,
        updatedAt: Date(timeIntervalSince1970: 100)
    )
}

@MainActor
private final class AccountBootstrapPipelineSpy: AccountBootstrapPipelining {
    let result: AccountBootstrapStatus
    private(set) var calls = 0

    init(result: AccountBootstrapStatus) {
        self.result = result
    }

    func run(
        initialStatus: AccountBootstrapStatus,
        session: AuthenticationSession,
        sourceKind: BootstrapSourceKind,
        progress: (AccountBootstrapStatus) -> Void
    ) async throws -> AccountBootstrapStatus {
        calls += 1
        progress(initialStatus)
        return result
    }
}

private struct CoordinatorFixture {
    let coordinator: AccountBootstrapCoordinator
    let session: BootstrapSessionSpy
    let notice: BootstrapNoticeSpy
    let api: AccountBootstrapAPISpy
    let checkpoint: BootstrapCheckpointStoreSpy
}

@MainActor
private final class BootstrapSessionSpy: BootstrapSessionControlling {
    var session: AuthenticationSession?
    private(set) var restoreCalls = 0
    private(set) var logoutCalls = 0

    init(session: AuthenticationSession?) {
        self.session = session
    }

    func authenticationSession() -> AuthenticationSession? { session }
    func restoreSession() async { restoreCalls += 1 }
    func logout() { logoutCalls += 1; session = nil }
}

@MainActor
private final class BootstrapNoticeSpy: BootstrapNoticeControlling {
    let hasLegacyData: Bool
    var hasAcknowledgedNotice: Bool
    private(set) var acknowledgeCalls = 0

    init(hasLegacyData: Bool, hasAcknowledgedNotice: Bool) {
        self.hasLegacyData = hasLegacyData
        self.hasAcknowledgedNotice = hasAcknowledgedNotice
    }

    func acknowledgeNotice() {
        acknowledgeCalls += 1
        hasAcknowledgedNotice = true
    }
}

@MainActor
private final class AccountBootstrapAPISpy: AccountBootstrapAPIProtocol {
    private var statuses: [AccountBootstrapStatus]
    private let responseDelayNanoseconds: UInt64
    private let ignoresCancellation: Bool
    private(set) var statusCalls = 0
    private(set) var resumeCalls = 0
    private(set) var resumeSourceKinds: [BootstrapSourceKind] = []

    init(
        statuses: [AccountBootstrapStatus],
        responseDelayNanoseconds: UInt64,
        ignoresCancellation: Bool
    ) {
        self.statuses = statuses
        self.responseDelayNanoseconds = responseDelayNanoseconds
        self.ignoresCancellation = ignoresCancellation
    }

    func status() async throws -> AccountBootstrapStatus {
        statusCalls += 1
        return try await nextStatus()
    }

    func resume(
        sourceKind: BootstrapSourceKind,
        vaultCheckpoint: VaultCheckpoint?
    ) async throws -> AccountBootstrapStatus {
        resumeCalls += 1
        resumeSourceKinds.append(sourceKind)
        return try await nextStatus()
    }

    private func nextStatus() async throws -> AccountBootstrapStatus {
        if responseDelayNanoseconds > 0 {
            if ignoresCancellation {
                try? await Task.sleep(nanoseconds: responseDelayNanoseconds)
            } else {
                try await Task.sleep(nanoseconds: responseDelayNanoseconds)
            }
        }
        return try XCTUnwrap(statuses.isEmpty ? nil : statuses.removeFirst())
    }
}

private final class BootstrapCheckpointStoreSpy: BootstrapCheckpointStoring {
    var stored: BootstrapCheckpoint?
    private(set) var clearCalls = 0

    func load() throws -> BootstrapCheckpoint? { stored }
    func save(_ checkpoint: BootstrapCheckpoint) throws { stored = checkpoint }
    func clear() { clearCalls += 1; stored = nil }
}
