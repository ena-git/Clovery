import XCTest
@testable import Clovery

final class AuthenticationSessionStoreTests: XCTestCase {
    func testSessionStoreReplacesRefreshTokenAtomically() throws {
        let keychain = KeychainStore(service: "com.clovery.tests.\(UUID().uuidString)")
        let store = AuthenticationSessionStore(keychain: keychain)
        defer { store.clear() }

        try store.save(session: makeSession(refreshToken: "old"))
        try store.replaceRefreshToken("new")

        XCTAssertEqual(try store.refreshToken(), "new")
    }

    func testClearRemovesOnlyAuthenticationCredentials() throws {
        let keychain = KeychainStore(service: "com.clovery.tests.\(UUID().uuidString)")
        let store = AuthenticationSessionStore(keychain: keychain)
        defer { store.clear() }

        try store.save(session: makeSession())
        store.clear()

        XCTAssertNil(try store.refreshToken())
    }

    private func makeSession(refreshToken: String = "refresh") -> AuthSessionResponse {
        AuthSessionResponse(
            accountID: "account",
            vaultID: "vault",
            accessToken: "access",
            accessTokenExpiresIn: 900,
            refreshToken: refreshToken,
            recoveryCodes: nil
        )
    }
}
