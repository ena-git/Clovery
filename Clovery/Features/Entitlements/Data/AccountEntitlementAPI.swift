import Foundation

enum AccountEntitlementEnvironment: String, Codable, CaseIterable, Sendable {
    case production
    case sandbox
}

enum AccountEntitlementState: String, Codable, Sendable {
    case active
    case expired
    case revoked
    case cancelled
    case failed
}

struct AccountEntitlementSummary: Codable, Equatable, Sendable {
    let productID: String
    let state: AccountEntitlementState
    let expiresAt: Date?
    let revokedAt: Date?
    let sourceStorefront: String
    let updatedAt: Date

    func isActive(at date: Date) -> Bool {
        guard state == .active, revokedAt == nil else { return false }
        return expiresAt.map { $0 > date } ?? true
    }
}

@MainActor
protocol AccountEntitlementAPIProtocol: AnyObject {
    func claimLegacy(
        signedTransactionInfo: String,
        environment: AccountEntitlementEnvironment
    ) async throws -> AccountEntitlementSummary
    func verify(
        transactionID: UInt64,
        environment: AccountEntitlementEnvironment
    ) async throws -> AccountEntitlementSummary
    func restore(
        transactionIDs: [UInt64],
        environment: AccountEntitlementEnvironment
    ) async throws -> [AccountEntitlementSummary]
    func list() async throws -> [AccountEntitlementSummary]
}

@MainActor
final class AccountEntitlementAPI: AccountEntitlementAPIProtocol {
    private let client: AuthenticatedAPIClient
    private let encoder: JSONEncoder

    init(client: AuthenticatedAPIClient, encoder: JSONEncoder = JSONEncoder()) {
        self.client = client
        self.encoder = encoder
    }

    func claimLegacy(
        signedTransactionInfo: String,
        environment: AccountEntitlementEnvironment
    ) async throws -> AccountEntitlementSummary {
        let body = try encoder.encode(LegacyClaimRequest(
            signedTransactionInfo: signedTransactionInfo,
            environment: environment
        ))
        let response: EntitlementWire = try await client.send(
            APIRequest(
                method: "POST",
                path: "/v1/billing/apple/legacy-claims",
                body: body,
                stableRequestID: "apple-legacy-claim"
            ),
            decoding: EntitlementWire.self
        )
        return try response.summary()
    }

    func verify(
        transactionID: UInt64,
        environment: AccountEntitlementEnvironment
    ) async throws -> AccountEntitlementSummary {
        let body = try encoder.encode(TransactionVerifyRequest(
            transactionID: String(transactionID),
            environment: environment
        ))
        let response: EntitlementWire = try await client.send(
            APIRequest(
                method: "POST",
                path: "/v1/billing/apple/transactions/verify",
                body: body,
                stableRequestID: "apple-transaction-verify"
            ),
            decoding: EntitlementWire.self
        )
        return try response.summary()
    }

    func restore(
        transactionIDs: [UInt64],
        environment: AccountEntitlementEnvironment
    ) async throws -> [AccountEntitlementSummary] {
        let body = try encoder.encode(RestoreRequest(
            transactionIDs: transactionIDs.map(String.init),
            environment: environment
        ))
        let response: EntitlementListWire = try await client.send(
            APIRequest(
                method: "POST",
                path: "/v1/billing/apple/restore",
                body: body,
                stableRequestID: "apple-restore-\(environment.rawValue)"
            ),
            decoding: EntitlementListWire.self
        )
        return try response.summaries()
    }

    func list() async throws -> [AccountEntitlementSummary] {
        let response: EntitlementListWire = try await client.send(
            APIRequest(method: "GET", path: "/v1/account/entitlements"),
            decoding: EntitlementListWire.self
        )
        return try response.summaries()
    }
}

private struct LegacyClaimRequest: Encodable {
    let signedTransactionInfo: String
    let environment: AccountEntitlementEnvironment

    enum CodingKeys: String, CodingKey {
        case signedTransactionInfo = "signed_transaction_info"
        case environment
    }
}

private struct TransactionVerifyRequest: Encodable {
    let transactionID: String
    let environment: AccountEntitlementEnvironment

    enum CodingKeys: String, CodingKey {
        case transactionID = "transaction_id"
        case environment
    }
}

private struct RestoreRequest: Encodable {
    let transactionIDs: [String]
    let environment: AccountEntitlementEnvironment

    enum CodingKeys: String, CodingKey {
        case transactionIDs = "transaction_ids"
        case environment
    }
}

private struct EntitlementListWire: Decodable {
    let entitlements: [EntitlementWire]

    func summaries() throws -> [AccountEntitlementSummary] {
        try entitlements.map { try $0.summary() }
    }
}

private struct EntitlementWire: Decodable {
    let productID: String
    let state: AccountEntitlementState
    let expiresAt: String?
    let revokedAt: String?
    let sourceStorefront: String
    let sourceTransactionID: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case state
        case expiresAt = "expires_at"
        case revokedAt = "revoked_at"
        case sourceStorefront = "source_storefront"
        case sourceTransactionID = "source_transaction_id"
        case updatedAt = "updated_at"
    }

    func summary() throws -> AccountEntitlementSummary {
        guard !productID.isEmpty, !sourceStorefront.isEmpty,
              !sourceTransactionID.isEmpty,
              let parsedUpdatedAt = EntitlementDateParser.parse(updatedAt)
        else {
            throw APIError.decoding("The entitlement response is invalid.")
        }
        let parsedExpiresAt = try EntitlementDateParser.parseOptional(expiresAt)
        let parsedRevokedAt = try EntitlementDateParser.parseOptional(revokedAt)
        return AccountEntitlementSummary(
            productID: productID,
            state: state,
            expiresAt: parsedExpiresAt,
            revokedAt: parsedRevokedAt,
            sourceStorefront: sourceStorefront,
            updatedAt: parsedUpdatedAt
        )
    }
}

private enum EntitlementDateParser {
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func parseOptional(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        guard let parsed = parse(value) else {
            throw APIError.decoding("The entitlement date is invalid.")
        }
        return parsed
    }
}
