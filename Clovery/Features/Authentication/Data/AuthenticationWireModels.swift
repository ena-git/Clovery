import Foundation

struct RegisterRequest: Encodable {
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

struct LoginRequest: Encodable {
    let loginID: String
    let password: String
    let device: DeviceRegistration

    enum CodingKeys: String, CodingKey {
        case loginID = "login_id"
        case password
        case device
    }
}

struct RefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct FederatedLoginCompleteRequest: Encodable {
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

enum FederatedLoginWireResponse: Decodable {
    case authenticated(AuthSessionResponse)
    case identityClaim(IdentityClaimRequiredResponse)

    private enum CodingKeys: String, CodingKey {
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decodeIfPresent(String.self, forKey: .status) == "identity_claim_required" {
            self = .identityClaim(try IdentityClaimRequiredResponse(from: decoder))
        } else {
            self = .authenticated(try AuthSessionResponse(from: decoder))
        }
    }
}

struct IdentityClaimRequiredResponse: Decodable {
    let provider: IdentityProvider
    let identityClaimToken: String
    let expiresIn: Int

    private enum CodingKeys: String, CodingKey {
        case status
        case provider
        case identityClaimToken = "identity_claim_token"
        case expiresIn = "expires_in"
        case accountID = "account_id"
        case vaultID = "vault_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard !container.contains(.accountID), !container.contains(.vaultID),
              try container.decode(String.self, forKey: .status) == "identity_claim_required"
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid identity claim response.")
            )
        }
        provider = try container.decode(IdentityProvider.self, forKey: .provider)
        guard provider == .apple || provider == .google || provider == .huawei else {
            throw DecodingError.dataCorruptedError(
                forKey: .provider, in: container, debugDescription: "Unsupported claim provider."
            )
        }
        identityClaimToken = try container.decode(String.self, forKey: .identityClaimToken)
        expiresIn = try container.decode(Int.self, forKey: .expiresIn)
        guard !identityClaimToken.isEmpty, expiresIn > 0 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid identity claim response.")
            )
        }
    }
}

struct PasskeyLoginCompleteRequest: Encodable {
    let challengeID: String
    let response: [String: JSONValue]
    let device: DeviceRegistration

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case response
        case device
    }
}

struct RecoveryCodeConsumeRequest: Encodable {
    let loginID: String
    let recoveryCode: String

    enum CodingKeys: String, CodingKey {
        case loginID = "login_id"
        case recoveryCode = "recovery_code"
    }
}

struct PasswordResetCompleteRequest: Encodable {
    let resetIntentID: String
    let proof: String
    let newPassword: String

    enum CodingKeys: String, CodingKey {
        case resetIntentID = "reset_intent_id"
        case proof
        case newPassword = "new_password"
    }
}
