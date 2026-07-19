@testable import Clovery

@MainActor
final class AuthenticationAPISpy: AuthenticationAPIProtocol {
    var registerResponse = AuthSessionResponse(
        accountID: "account",
        vaultID: "vault",
        accessToken: "access",
        accessTokenExpiresIn: 900,
        refreshToken: "refresh",
        recoveryCodes: nil
    )
    var registerError: Error?
    var loginError: Error?
    var loginDelayNanoseconds: UInt64 = 0
    private(set) var registerCallCount = 0
    private(set) var loginCallCount = 0

    func register(
        loginID: String,
        password: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        return registerResponse
    }

    func login(
        loginID: String,
        password: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        loginCallCount += 1
        if loginDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: loginDelayNanoseconds)
        }
        if let loginError {
            throw loginError
        }
        return registerResponse
    }

    func refresh(refreshToken: String) async throws -> AuthSessionResponse {
        registerResponse
    }

    func startFederatedLogin(provider: IdentityProvider) async throws -> FederationIntentResponse {
        FederationIntentResponse(intentID: "intent", provider: provider.rawValue, nonce: "nonce", expiresIn: 300)
    }

    func completeFederatedLogin(
        provider: IdentityProvider,
        intentID: String,
        nonce: String,
        authorizationCode: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        registerResponse
    }

    func startPasskeyLogin() async throws -> PasskeyCeremonyResponse {
        PasskeyCeremonyResponse(challengeID: "challenge", options: [:], expiresIn: 300)
    }

    func completePasskeyLogin(
        challengeID: String,
        response: [String: JSONValue],
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        registerResponse
    }

    func consumeRecoveryCode(
        loginID: String,
        recoveryCode: String
    ) async throws -> RecoveryProofResponse {
        RecoveryProofResponse(
            resetIntentID: "reset-intent",
            recoveryProof: "reset-proof",
            expiresIn: 600
        )
    }

    func completePasswordReset(
        resetIntentID: String,
        proof: String,
        newPassword: String
    ) async throws {}
}
