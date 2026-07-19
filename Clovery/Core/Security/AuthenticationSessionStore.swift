import Foundation

final class AuthenticationSessionStore {
    static let refreshTokenAccount = "refresh-token"

    private let keychain: KeychainStoring

    init(keychain: KeychainStoring = KeychainStore()) {
        self.keychain = keychain
    }

    func save(session: AuthSessionResponse) throws {
        try keychain.save(session.refreshToken, account: Self.refreshTokenAccount)
    }

    func replaceRefreshToken(_ refreshToken: String) throws {
        try keychain.save(refreshToken, account: Self.refreshTokenAccount)
    }

    func refreshToken() throws -> String? {
        try keychain.read(account: Self.refreshTokenAccount)
    }

    func clear() {
        try? keychain.delete(account: Self.refreshTokenAccount)
    }
}
