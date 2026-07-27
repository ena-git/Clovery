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
