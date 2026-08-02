import Foundation
import XCTest
@testable import Clovery

@MainActor
final class AccountSecurityViewModelTests: XCTestCase {
    func testDeletionViewExplainsAllScheduledServerData() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(
                    "Clovery/Features/Account/Presentation/DeleteAccountConfirmationView.swift"
                ),
            encoding: .utf8
        )

        for requiredCopy in ["Clovery 账户", "Vault", "照片", "服务端权益", "计划删除"] {
            XCTAssertTrue(source.contains(requiredCopy), "Missing deletion copy: \(requiredCopy)")
        }
        XCTAssertTrue(source.contains("canConfirmDeletion"))
        XCTAssertTrue(source.contains(".cloveryFont"))
    }

    func testLoadShowsCloveryIDAndProviderNamesWithoutIdentitySubjects() async {
        let fixture = makeFixture()

        await fixture.viewModel.load()

        XCTAssertEqual(fixture.viewModel.cloveryID, "garden_user")
        XCTAssertEqual(fixture.viewModel.providerNames, ["Apple", "Google", "华为"])
        XCTAssertNil(fixture.viewModel.errorMessage)
    }

    func testDeletionRequiresExactCloveryIDBeforeCallingAPI() async {
        let fixture = makeFixture()
        await fixture.viewModel.load()

        await fixture.viewModel.requestDeletion(confirmation: "Garden_User")

        XCTAssertEqual(fixture.api.deletionCalls, 0)
        XCTAssertFalse(fixture.viewModel.didAcceptDeletion)
        XCTAssertNotNil(fixture.viewModel.errorMessage)
    }

    func testAcceptedDeletionClearsEntitlementStateAndLogsOutImmediately() async {
        let fixture = makeFixture()
        await fixture.viewModel.load()

        await fixture.viewModel.requestDeletion(confirmation: "garden_user")

        XCTAssertEqual(fixture.api.deletionCalls, 1)
        XCTAssertEqual(fixture.cache.clearCalls, 1)
        XCTAssertEqual(fixture.entitlementState.resetCalls, 1)
        XCTAssertEqual(fixture.session.logoutCalls, 1)
        XCTAssertTrue(fixture.viewModel.didAcceptDeletion)
    }

    func testFailedDeletionKeepsSessionAndOffersRetryWithoutServerDetails() async {
        let fixture = makeFixture()
        fixture.api.deletionError = APIError.server(
            code: "database_internal_detail",
            message: "sensitive database detail",
            statusCode: 503
        )
        await fixture.viewModel.load()

        await fixture.viewModel.requestDeletion(confirmation: "garden_user")

        XCTAssertEqual(fixture.session.logoutCalls, 0)
        XCTAssertEqual(fixture.cache.clearCalls, 0)
        XCTAssertEqual(fixture.entitlementState.resetCalls, 0)
        XCTAssertFalse(fixture.viewModel.didAcceptDeletion)
        XCTAssertEqual(fixture.viewModel.errorMessage, "账户删除请求失败，请检查网络后重试")
    }

    func testReloadFailureDoesNotKeepStaleAccountSummary() async {
        let fixture = makeFixture()
        await fixture.viewModel.load()
        fixture.api.summaryError = APIError.transport("offline")

        await fixture.viewModel.load()

        XCTAssertNil(fixture.viewModel.summary)
        XCTAssertNil(fixture.viewModel.cloveryID)
        XCTAssertNotNil(fixture.viewModel.errorMessage)
    }

    func testAcceptedDeletionStillLogsOutWhenLocalCacheCleanupFails() async {
        let fixture = makeFixture()
        fixture.cache.error = CocoaError(.fileWriteUnknown)
        await fixture.viewModel.load()

        await fixture.viewModel.requestDeletion(confirmation: "garden_user")

        XCTAssertEqual(fixture.entitlementState.resetCalls, 1)
        XCTAssertEqual(fixture.session.logoutCalls, 1)
        XCTAssertTrue(fixture.viewModel.didAcceptDeletion)
        XCTAssertEqual(fixture.viewModel.cleanupWarning, "账户已进入删除流程，但本地权益缓存清理未完成")
    }

    private func makeFixture() -> AccountSecurityFixture {
        let api = AccountManagementAPISpy()
        let session = AccountDeletionSessionSpy()
        let cache = AccountEntitlementCacheClearSpy()
        let entitlementState = AccountEntitlementStateResetSpy()
        let viewModel = AccountSecurityViewModel(
            api: api,
            session: session,
            entitlementCache: cache,
            entitlementState: entitlementState
        )
        return AccountSecurityFixture(
            viewModel: viewModel,
            api: api,
            session: session,
            cache: cache,
            entitlementState: entitlementState
        )
    }
}

@MainActor
private final class AccountManagementAPISpy: AccountManagementAPIProtocol {
    var summaryValue = AccountSummary(
        cloveryID: "garden_user",
        status: .active,
        createdAt: Date(timeIntervalSince1970: 100),
        hasPassword: true,
        passkeyCount: 0,
        recoveryCodesRemaining: 8,
        bindings: [
            AccountBinding(provider: .apple),
            AccountBinding(provider: .google),
            AccountBinding(provider: .huawei)
        ]
    )
    var summaryError: Error?
    var deletionError: Error?
    private(set) var deletionCalls = 0

    func summary() async throws -> AccountSummary {
        if let summaryError { throw summaryError }
        return summaryValue
    }

    func requestDeletion() async throws -> AccountDeletionRequest {
        deletionCalls += 1
        if let deletionError { throw deletionError }
        return AccountDeletionRequest(
            requestID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            status: .pending,
            requestedAt: Date(timeIntervalSince1970: 100),
            scheduledFor: Date(timeIntervalSince1970: 200)
        )
    }
}

@MainActor
private final class AccountDeletionSessionSpy: AccountDeletionSessionEnding {
    private(set) var logoutCalls = 0
    func logout() { logoutCalls += 1 }
}

@MainActor
private final class AccountEntitlementCacheClearSpy: AccountEntitlementCacheClearing {
    var error: Error?
    private(set) var clearCalls = 0

    func clear() throws {
        clearCalls += 1
        if let error { throw error }
    }
}

@MainActor
private final class AccountEntitlementStateResetSpy: AccountEntitlementStateResetting {
    private(set) var resetCalls = 0
    func resetAccountEntitlementState() { resetCalls += 1 }
}

private struct AccountSecurityFixture {
    let viewModel: AccountSecurityViewModel
    let api: AccountManagementAPISpy
    let session: AccountDeletionSessionSpy
    let cache: AccountEntitlementCacheClearSpy
    let entitlementState: AccountEntitlementStateResetSpy
}
