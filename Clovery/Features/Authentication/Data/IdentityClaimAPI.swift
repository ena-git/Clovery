import Foundation

protocol IdentityClaimAPIProtocol {
    func register(
        loginID: String,
        password: String,
        claim: IdentityClaimContext,
        registrationRequestID: UUID,
        sourceKind: BootstrapSourceKind,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse
}

final class IdentityClaimAPI: IdentityClaimAPIProtocol {
    private let client: APIClient
    private let encoder: JSONEncoder

    init(client: APIClient, encoder: JSONEncoder = JSONEncoder()) {
        self.client = client
        self.encoder = encoder
    }

    func register(
        loginID: String,
        password: String,
        claim: IdentityClaimContext,
        registrationRequestID: UUID,
        sourceKind: BootstrapSourceKind,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        let body = try encoder.encode(
            IdentityClaimRegistrationRequest(
                loginID: loginID,
                password: password,
                recoveryMethod: "bound_identity",
                identityClaimToken: claim.token,
                registrationRequestID: registrationRequestID,
                sourceKind: sourceKind,
                device: device
            )
        )
        return try await client.send(
            APIRequest(method: "POST", path: "/v1/auth/accounts", body: body),
            decoding: AuthSessionResponse.self
        )
    }
}

private struct IdentityClaimRegistrationRequest: Encodable {
    let loginID: String
    let password: String
    let recoveryMethod: String
    let identityClaimToken: String
    let registrationRequestID: UUID
    let sourceKind: BootstrapSourceKind
    let device: DeviceRegistration

    enum CodingKeys: String, CodingKey {
        case loginID = "login_id"
        case password
        case recoveryMethod = "recovery_method"
        case identityClaimToken = "identity_claim_token"
        case registrationRequestID = "registration_request_id"
        case sourceKind = "source_kind"
        case device
    }
}
