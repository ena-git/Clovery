import Foundation

protocol AuthenticationAPIProtocol {
    func register(
        loginID: String,
        password: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse

    func login(
        loginID: String,
        password: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse

    func refresh(refreshToken: String) async throws -> AuthSessionResponse

    func startFederatedLogin(
        provider: IdentityProvider
    ) async throws -> FederationIntentResponse

    func completeFederatedLogin(
        provider: IdentityProvider,
        intentID: String,
        nonce: String,
        authorizationCode: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse

    func startPasskeyLogin() async throws -> PasskeyCeremonyResponse

    func completePasskeyLogin(
        challengeID: String,
        response: [String: JSONValue],
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse
}

final class AuthenticationAPI: AuthenticationAPIProtocol {
    private let client: APIClient
    private let encoder: JSONEncoder

    init(client: APIClient, encoder: JSONEncoder = JSONEncoder()) {
        self.client = client
        self.encoder = encoder
    }

    func register(
        loginID: String,
        password: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        let body = try encoder.encode(
            RegisterRequest(
                loginID: loginID,
                password: password,
                recoveryMethod: "recovery_codes",
                device: device
            )
        )
        return try await client.send(
            APIRequest(method: "POST", path: "/v1/auth/accounts", body: body),
            decoding: AuthSessionResponse.self
        )
    }

    func login(
        loginID: String,
        password: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        let body = try encoder.encode(LoginRequest(loginID: loginID, password: password, device: device))
        return try await client.send(
            APIRequest(method: "POST", path: "/v1/auth/password/login", body: body),
            decoding: AuthSessionResponse.self
        )
    }

    func refresh(refreshToken: String) async throws -> AuthSessionResponse {
        let body = try encoder.encode(RefreshRequest(refreshToken: refreshToken))
        return try await client.send(
            APIRequest(method: "POST", path: "/v1/auth/sessions/refresh", body: body),
            decoding: AuthSessionResponse.self
        )
    }

    func startFederatedLogin(
        provider: IdentityProvider
    ) async throws -> FederationIntentResponse {
        try await client.send(
            APIRequest(method: "POST", path: "/v1/auth/federated/\(provider.rawValue)/start"),
            decoding: FederationIntentResponse.self
        )
    }

    func completeFederatedLogin(
        provider: IdentityProvider,
        intentID: String,
        nonce: String,
        authorizationCode: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        let body = try encoder.encode(
            FederatedLoginCompleteRequest(
                intentID: intentID,
                nonce: nonce,
                authorizationCode: authorizationCode,
                device: device
            )
        )
        return try await client.send(
            APIRequest(
                method: "POST",
                path: "/v1/auth/federated/\(provider.rawValue)/complete",
                body: body
            ),
            decoding: AuthSessionResponse.self
        )
    }

    func startPasskeyLogin() async throws -> PasskeyCeremonyResponse {
        try await client.send(
            APIRequest(method: "POST", path: "/v1/auth/passkeys/login/start"),
            decoding: PasskeyCeremonyResponse.self
        )
    }

    func completePasskeyLogin(
        challengeID: String,
        response: [String: JSONValue],
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        let body = try encoder.encode(
            PasskeyLoginCompleteRequest(
                challengeID: challengeID,
                response: response,
                device: device
            )
        )
        return try await client.send(
            APIRequest(
                method: "POST",
                path: "/v1/auth/passkeys/login/complete",
                body: body
            ),
            decoding: AuthSessionResponse.self
        )
    }
}

private struct RegisterRequest: Encodable {
    let loginID: String
    let password: String
    let recoveryMethod: String
    let device: DeviceRegistration

    enum CodingKeys: String, CodingKey {
        case loginID = "login_id"
        case password
        case recoveryMethod = "recovery_method"
        case device
    }
}

private struct LoginRequest: Encodable {
    let loginID: String
    let password: String
    let device: DeviceRegistration

    enum CodingKeys: String, CodingKey {
        case loginID = "login_id"
        case password
        case device
    }
}

private struct RefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private struct FederatedLoginCompleteRequest: Encodable {
    let intentID: String
    let nonce: String
    let authorizationCode: String
    let device: DeviceRegistration

    enum CodingKeys: String, CodingKey {
        case intentID = "intent_id"
        case nonce
        case authorizationCode = "authorization_code"
        case device
    }
}

private struct PasskeyLoginCompleteRequest: Encodable {
    let challengeID: String
    let response: [String: JSONValue]
    let device: DeviceRegistration

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case response
        case device
    }
}
