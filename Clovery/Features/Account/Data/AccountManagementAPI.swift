import Foundation

enum AccountStatus: String, Equatable {
    case active
    case deletionRequested = "deletion_requested"
    case deleting
    case deleted
}

struct AccountBinding: Equatable {
    let provider: AccountIdentityProvider
}

enum AccountIdentityProvider: String, Equatable {
    case apple
    case google
    case huawei
    case wechat
    case qq
}

struct AccountSummary: Equatable {
    let cloveryID: String
    let status: AccountStatus
    let createdAt: Date
    let hasPassword: Bool
    let passkeyCount: Int
    let recoveryCodesRemaining: Int
    let bindings: [AccountBinding]
}

enum AccountDeletionStatus: String, Equatable {
    case pending
    case processing
    case completed
    case cancelled
}

struct AccountDeletionRequest: Equatable {
    let requestID: UUID
    let status: AccountDeletionStatus
    let requestedAt: Date
    let scheduledFor: Date
}

@MainActor
protocol AccountManagementAPIProtocol: AnyObject {
    func summary() async throws -> AccountSummary
    func requestDeletion() async throws -> AccountDeletionRequest
}

@MainActor
final class AccountManagementAPI: AccountManagementAPIProtocol {
    private let client: AuthenticatedAPIClient

    init(client: AuthenticatedAPIClient) {
        self.client = client
    }

    func summary() async throws -> AccountSummary {
        do {
            let response: AccountSummaryWire = try await client.send(
                APIRequest(method: "GET", path: "/v1/account"),
                decoding: AccountSummaryWire.self
            )
            return try response.summary()
        } catch let error as APIError {
            guard case .decoding = error else { throw error }
            throw APIError.decoding("The account response is invalid.")
        }
    }

    func requestDeletion() async throws -> AccountDeletionRequest {
        do {
            let response: AccountDeletionRequestWire = try await client.send(
                APIRequest(
                    method: "POST",
                    path: "/v1/account/deletion-requests",
                    stableRequestID: "account-deletion-request"
                ),
                decoding: AccountDeletionRequestWire.self
            )
            return try response.request()
        } catch let error as APIError {
            guard case .decoding = error else { throw error }
            throw APIError.decoding("The account deletion response is invalid.")
        }
    }
}

private struct AccountSummaryWire: Decodable {
    let accountID: String
    let cloveryID: String
    let status: String
    let createdAt: String
    let hasPassword: Bool
    let passkeyCount: Int
    let recoveryCodesRemaining: Int
    let bindings: [AccountBindingWire]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case accountID = "account_id"
        case cloveryID = "clovery_id"
        case status
        case createdAt = "created_at"
        case hasPassword = "has_password"
        case passkeyCount = "passkey_count"
        case recoveryCodesRemaining = "recovery_codes_remaining"
        case bindings
    }

    init(from decoder: Decoder) throws {
        try rejectUnexpectedKeys(
            from: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accountID = try container.decode(String.self, forKey: .accountID)
        cloveryID = try container.decode(String.self, forKey: .cloveryID)
        status = try container.decode(String.self, forKey: .status)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        hasPassword = try container.decode(Bool.self, forKey: .hasPassword)
        passkeyCount = try container.decode(Int.self, forKey: .passkeyCount)
        recoveryCodesRemaining = try container.decode(
            Int.self,
            forKey: .recoveryCodesRemaining
        )
        bindings = try container.decode([AccountBindingWire].self, forKey: .bindings)
    }

    func summary() throws -> AccountSummary {
        guard let accountUUID = UUID(uuidString: accountID),
              accountUUID != UUID.zero,
              AuthenticationValidation.isValidCloveryID(cloveryID),
              AuthenticationValidation.normalizedCloveryID(cloveryID) == cloveryID,
              let parsedStatus = AccountStatus(rawValue: status),
              let parsedCreatedAt = AccountDateParser.parse(createdAt),
              passkeyCount >= 0,
              recoveryCodesRemaining >= 0
        else {
            throw APIError.decoding("The account response is invalid.")
        }

        return AccountSummary(
            cloveryID: cloveryID,
            status: parsedStatus,
            createdAt: parsedCreatedAt,
            hasPassword: hasPassword,
            passkeyCount: passkeyCount,
            recoveryCodesRemaining: recoveryCodesRemaining,
            bindings: try bindings.map { try $0.binding() }
        )
    }
}

private struct AccountBindingWire: Decodable {
    let provider: String
    let issuer: String
    let createdAt: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case provider
        case issuer
        case createdAt = "created_at"
    }

    func binding() throws -> AccountBinding {
        guard let parsedProvider = AccountIdentityProvider(rawValue: provider),
              !issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              AccountDateParser.parse(createdAt) != nil
        else {
            throw APIError.decoding("The account binding response is invalid.")
        }
        return AccountBinding(provider: parsedProvider)
    }

    init(from decoder: Decoder) throws {
        try rejectUnexpectedKeys(
            from: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(String.self, forKey: .provider)
        issuer = try container.decode(String.self, forKey: .issuer)
        createdAt = try container.decode(String.self, forKey: .createdAt)
    }
}

private struct AccountDeletionRequestWire: Decodable {
    let requestID: String
    let status: String
    let requestedAt: String
    let scheduledFor: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case requestID = "request_id"
        case status
        case requestedAt = "requested_at"
        case scheduledFor = "scheduled_for"
    }

    func request() throws -> AccountDeletionRequest {
        guard let parsedRequestID = UUID(uuidString: requestID),
              parsedRequestID != UUID.zero,
              let parsedStatus = AccountDeletionStatus(rawValue: status),
              let parsedRequestedAt = AccountDateParser.parse(requestedAt),
              let parsedScheduledFor = AccountDateParser.parse(scheduledFor),
              parsedScheduledFor > parsedRequestedAt
        else {
            throw APIError.decoding("The account deletion response is invalid.")
        }
        return AccountDeletionRequest(
            requestID: parsedRequestID,
            status: parsedStatus,
            requestedAt: parsedRequestedAt,
            scheduledFor: parsedScheduledFor
        )
    }

    init(from decoder: Decoder) throws {
        try rejectUnexpectedKeys(
            from: decoder,
            allowed: Set(CodingKeys.allCases.map(\.rawValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(String.self, forKey: .requestID)
        status = try container.decode(String.self, forKey: .status)
        requestedAt = try container.decode(String.self, forKey: .requestedAt)
        scheduledFor = try container.decode(String.self, forKey: .scheduledFor)
    }
}

private enum AccountDateParser {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private extension UUID {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

private struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
    }
}

private func rejectUnexpectedKeys(
    from decoder: Decoder,
    allowed: Set<String>
) throws {
    let container = try decoder.container(keyedBy: AnyCodingKey.self)
    guard let unexpectedKey = container.allKeys.first(where: {
        !allowed.contains($0.stringValue)
    }) else {
        return
    }
    throw DecodingError.dataCorruptedError(
        forKey: unexpectedKey,
        in: container,
        debugDescription: "Unexpected response field."
    )
}
