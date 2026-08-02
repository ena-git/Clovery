import Foundation

struct AuthenticationSession: Equatable {
    let accountID: String
    let vaultID: String
    let accessToken: String
    let accessTokenExpiresAt: Date
}

enum AuthenticationState: Equatable {
    case unauthenticated
    case authenticated(AuthenticationSession)
    case recoveryCodes(AuthenticationSession, [String])

    var requiresRecoveryCodeAcknowledgement: Bool {
        if case .recoveryCodes = self {
            return true
        }
        return false
    }

    var session: AuthenticationSession? {
        switch self {
        case .unauthenticated:
            return nil
        case let .authenticated(session), let .recoveryCodes(session, _):
            return session
        }
    }
}
