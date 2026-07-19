import Foundation

struct DeviceRegistration: Codable, Equatable {
    let deviceID: String
    let platform: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case platform
        case displayName = "display_name"
    }
}

struct AuthSessionResponse: Codable, Equatable {
    let accountID: String
    let vaultID: String
    let accessToken: String
    let accessTokenExpiresIn: Int
    let refreshToken: String
    let recoveryCodes: [String]?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case vaultID = "vault_id"
        case accessToken = "access_token"
        case accessTokenExpiresIn = "access_token_expires_in"
        case refreshToken = "refresh_token"
        case recoveryCodes = "recovery_codes"
    }
}

struct FederationIntentResponse: Codable, Equatable {
    let intentID: String
    let provider: String
    let nonce: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case intentID = "intent_id"
        case provider
        case nonce
        case expiresIn = "expires_in"
    }
}

enum IdentityProvider: String, Codable, CaseIterable {
    case apple
    case google
    case huawei
    case wechat
    case qq
}

struct PasswordResetStartResponse: Codable, Equatable {
    let accepted: Bool
    let resetIntentID: String?
    let challenge: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accepted
        case resetIntentID = "reset_intent_id"
        case challenge
        case expiresIn = "expires_in"
    }
}

struct RecoveryProofResponse: Codable, Equatable {
    let resetIntentID: String
    let recoveryProof: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case resetIntentID = "reset_intent_id"
        case recoveryProof = "recovery_proof"
        case expiresIn = "expires_in"
    }
}

struct PasskeyCeremonyResponse: Codable, Equatable {
    let challengeID: String
    let options: [String: JSONValue]
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case options
        case expiresIn = "expires_in"
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
