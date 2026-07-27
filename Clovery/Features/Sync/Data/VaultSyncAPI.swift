import Foundation

struct VaultSyncOperation: Codable, Equatable {
    let operationID: UUID
    let entryID: String
    let baseRevision: Int
    let payload: JSONValue
    let deleted: Bool

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case entryID = "entry_id"
        case baseRevision = "base_revision"
        case payload
        case deleted
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operationID.uuidString.lowercased(), forKey: .operationID)
        try container.encode(entryID, forKey: .entryID)
        try container.encode(baseRevision, forKey: .baseRevision)
        try container.encode(payload, forKey: .payload)
        try container.encode(deleted, forKey: .deleted)
    }
}

enum VaultSyncDecisionStatus: String, Codable, Equatable {
    case applied
    case conflict
}

struct VaultSyncEntry: Codable, Equatable {
    let entryID: String
    let revision: Int
    let payload: JSONValue
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case entryID = "entry_id"
        case revision
        case payload
        case deletedAt = "deleted_at"
    }
}

struct VaultSyncDecision: Codable, Equatable {
    let operationID: UUID
    let status: VaultSyncDecisionStatus
    let entry: VaultSyncEntry?
    let serverSnapshot: VaultSyncEntry?
    let cursor: Int64?

    enum CodingKeys: String, CodingKey {
        case operationID = "operation_id"
        case status
        case entry
        case serverSnapshot = "server_snapshot"
        case cursor
    }
}

struct VaultSyncChange: Codable, Equatable {
    let cursor: Int64
    let entityType: String
    let entityID: String
    let revision: Int
    let operationID: UUID
    let payload: JSONValue
    let deleted: Bool
    let changedAt: String

    enum CodingKeys: String, CodingKey {
        case cursor
        case entityType = "entity_type"
        case entityID = "entity_id"
        case revision
        case operationID = "operation_id"
        case payload
        case deleted
        case changedAt = "changed_at"
    }
}

struct VaultSyncPage: Codable, Equatable {
    let changes: [VaultSyncChange]
    let nextCursor: Int64
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case changes
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

@MainActor
protocol VaultSyncAPIProtocol: AnyObject {
    func push(_ operations: [VaultSyncOperation]) async throws -> [VaultSyncDecision]
    func pull(cursor: Int64, limit: Int) async throws -> VaultSyncPage
}

@MainActor
final class VaultSyncAPI: VaultSyncAPIProtocol {
    private let client: AuthenticatedAPIClient
    private let encoder: JSONEncoder

    init(client: AuthenticatedAPIClient, encoder: JSONEncoder = JSONEncoder()) {
        self.client = client
        self.encoder = encoder
    }

    func push(_ operations: [VaultSyncOperation]) async throws -> [VaultSyncDecision] {
        let body = try encoder.encode(VaultSyncPushRequest(operations: operations))
        let response: VaultSyncPushResponse = try await client.send(
            APIRequest(
                method: "POST",
                path: "/v1/vault/sync/push",
                body: body,
                stableRequestID: operations.map(\.operationID.uuidString).joined(separator: ",")
            ),
            decoding: VaultSyncPushResponse.self
        )
        return response.results
    }

    func pull(cursor: Int64, limit: Int) async throws -> VaultSyncPage {
        try await client.send(
            APIRequest(
                method: "GET",
                path: "/v1/vault/sync/pull",
                queryItems: [
                    URLQueryItem(name: "cursor", value: String(cursor)),
                    URLQueryItem(name: "limit", value: String(limit))
                ]
            ),
            decoding: VaultSyncPage.self
        )
    }
}

private struct VaultSyncPushRequest: Encodable {
    let operations: [VaultSyncOperation]
}

private struct VaultSyncPushResponse: Decodable {
    let results: [VaultSyncDecision]
}
