import XCTest
@testable import Clovery

@MainActor
final class ApplicationSessionControllerTests: XCTestCase {
    func testRefreshAuthenticatedSessionPersistsRotatedRefreshToken() async throws {
        let keychain = InMemoryKeychainStore()
        let sessionStore = AuthenticationSessionStore(keychain: keychain)
        let api = AuthenticationAPISpy()
        let controller = ApplicationSessionController(
            api: api,
            sessionStore: sessionStore,
            deviceIdentityStore: DeviceIdentityStore(keychain: InMemoryKeychainStore())
        )
        try controller.accept(makeResponse(refreshToken: "old-refresh"))
        api.registerResponse = makeResponse(
            accessToken: "rotated-access",
            refreshToken: "rotated-refresh"
        )

        let session = try await controller.refreshAuthenticatedSession()

        XCTAssertEqual(api.lastRefreshToken, "old-refresh")
        XCTAssertEqual(session.accessToken, "rotated-access")
        XCTAssertEqual(try sessionStore.refreshToken(), "rotated-refresh")
    }

    func testTransientRestoreFailurePreservesRefreshCredential() async throws {
        let fixture = makeFixture()
        try fixture.controller.accept(makeResponse(refreshToken: "keep-refresh"))
        fixture.api.refreshError = APIError.transport("offline")

        await fixture.controller.restoreSession()

        XCTAssertEqual(try fixture.sessionStore.refreshToken(), "keep-refresh")
    }

    func testTerminalRestoreRejectionClearsRefreshCredential() async throws {
        let fixture = makeFixture()
        try fixture.controller.accept(makeResponse(refreshToken: "rejected-refresh"))
        fixture.api.refreshError = APIError.server(
            code: "invalid_refresh_token",
            message: "Authentication failed.",
            statusCode: 401
        )

        await fixture.controller.restoreSession()

        XCTAssertNil(try fixture.sessionStore.refreshToken())
    }

    private func makeFixture() -> SessionFixture {
        let keychain = InMemoryKeychainStore()
        let sessionStore = AuthenticationSessionStore(keychain: keychain)
        let api = AuthenticationAPISpy()
        let controller = ApplicationSessionController(
            api: api,
            sessionStore: sessionStore,
            deviceIdentityStore: DeviceIdentityStore(keychain: InMemoryKeychainStore())
        )
        return SessionFixture(
            api: api,
            sessionStore: sessionStore,
            controller: controller
        )
    }

    private func makeResponse(
        accessToken: String = "access",
        refreshToken: String
    ) -> AuthSessionResponse {
        AuthSessionResponse(
            accountID: "account",
            vaultID: "vault",
            accessToken: accessToken,
            accessTokenExpiresIn: 900,
            refreshToken: refreshToken,
            recoveryCodes: nil
        )
    }
}

private struct SessionFixture {
    let api: AuthenticationAPISpy
    let sessionStore: AuthenticationSessionStore
    let controller: ApplicationSessionController
}

private final class InMemoryKeychainStore: KeychainStoring {
    private var values: [String: String] = [:]

    func save(_ value: String, account: String) throws {
        values[account] = value
    }

    func read(account: String) throws -> String? {
        values[account]
    }

    func delete(account: String) throws {
        values.removeValue(forKey: account)
    }
}
