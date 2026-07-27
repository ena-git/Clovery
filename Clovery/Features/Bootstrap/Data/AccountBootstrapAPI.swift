import Foundation

enum AccountBootstrapStageState: String, Codable, Equatable {
    case pending
    case complete
    case needsAttention = "needs_attention"
}

enum AccountBootstrapOverallState: Equatable {
    case pending
    case running
    case needsAttention(String)
    case complete
}

struct AccountBootstrapStages: Equatable {
    let identity: AccountBootstrapStageState
    let migration: AccountBootstrapStageState
    let entitlement: AccountBootstrapStageState
    let vault: AccountBootstrapStageState
}

struct AccountBootstrapStatus: Equatable {
    let overall: AccountBootstrapOverallState
    let sourceKind: BootstrapSourceKind
    let migrationID: UUID?
    let stages: AccountBootstrapStages
    let lastErrorCode: String?
    let retryCount: Int
    let updatedAt: Date
}

struct VaultCheckpoint: Codable, Equatable {
    let cursor: Int64
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case cursor
        case hasMore = "has_more"
    }
}

@MainActor
protocol AccountBootstrapAPIProtocol: AnyObject {
    func status() async throws -> AccountBootstrapStatus
    func resume(
        sourceKind: BootstrapSourceKind,
        vaultCheckpoint: VaultCheckpoint?
    ) async throws -> AccountBootstrapStatus
}

@MainActor
final class AccountBootstrapAPI: AccountBootstrapAPIProtocol {
    private let client: AuthenticatedAPIClient
    private let encoder: JSONEncoder

    init(client: AuthenticatedAPIClient, encoder: JSONEncoder = JSONEncoder()) {
        self.client = client
        self.encoder = encoder
    }

    func status() async throws -> AccountBootstrapStatus {
        let wire: AccountBootstrapWireResponse = try await client.send(
            APIRequest(method: "GET", path: "/v1/account/bootstrap"),
            decoding: AccountBootstrapWireResponse.self
        )
        return wire.resolvedStatus
    }

    func resume(
        sourceKind: BootstrapSourceKind,
        vaultCheckpoint: VaultCheckpoint?
    ) async throws -> AccountBootstrapStatus {
        let body = try encoder.encode(
            AccountBootstrapResumeRequest(
                sourceKind: sourceKind,
                vaultCheckpoint: vaultCheckpoint
            )
        )
        let wire: AccountBootstrapWireResponse = try await client.send(
            APIRequest(
                method: "POST",
                path: "/v1/account/bootstrap/resume",
                body: body,
                stableRequestID: "bootstrap-resume-\(sourceKind.rawValue)"
            ),
            decoding: AccountBootstrapWireResponse.self
        )
        return wire.resolvedStatus
    }
}

private struct AccountBootstrapResumeRequest: Encodable {
    let sourceKind: BootstrapSourceKind
    let vaultCheckpoint: VaultCheckpoint?

    enum CodingKeys: String, CodingKey {
        case sourceKind = "source_kind"
        case vaultCheckpoint = "vault_checkpoint"
    }
}

private struct AccountBootstrapWireResponse: Decodable {
    let rawStatus: String
    let sourceKind: String
    let migrationID: String?
    let stages: AccountBootstrapWireStages
    let lastErrorCode: String?
    let retryCount: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case rawStatus = "status"
        case sourceKind = "source_kind"
        case migrationID = "migration_id"
        case stages
        case lastErrorCode = "last_error_code"
        case retryCount = "retry_count"
        case updatedAt = "updated_at"
    }

    var statusValue: AccountBootstrapStatus? {
        let parsedMigrationID: UUID?
        if let migrationID {
            guard let value = UUID(uuidString: migrationID) else {
                return nil
            }
            parsedMigrationID = value
        } else {
            parsedMigrationID = nil
        }

        guard
            let sourceKind = BootstrapSourceKind(rawValue: sourceKind),
            let identity = AccountBootstrapStageState(rawValue: stages.identity),
            let migration = AccountBootstrapStageState(rawValue: stages.migration),
            let entitlement = AccountBootstrapStageState(rawValue: stages.entitlement),
            let vault = AccountBootstrapStageState(rawValue: stages.vault),
            retryCount >= 0,
            let updatedAt = Self.parseDate(updatedAt)
        else {
            return nil
        }

        let overall: AccountBootstrapOverallState
        switch rawStatus {
        case "pending":
            overall = .pending
        case "running":
            overall = .running
        case "needs_attention":
            overall = .needsAttention(lastErrorCode ?? "bootstrap_needs_attention")
        case "complete":
            guard identity == .complete,
                  migration == .complete,
                  entitlement == .complete,
                  vault == .complete
            else {
                return nil
            }
            overall = .complete
        default:
            return nil
        }

        return AccountBootstrapStatus(
            overall: overall,
            sourceKind: sourceKind,
            migrationID: parsedMigrationID,
            stages: AccountBootstrapStages(
                identity: identity,
                migration: migration,
                entitlement: entitlement,
                vault: vault
            ),
            lastErrorCode: lastErrorCode,
            retryCount: retryCount,
            updatedAt: updatedAt
        )
    }

    var resolvedStatus: AccountBootstrapStatus {
        statusValue ?? Self.contractUnknownStatus
    }

    private static let contractUnknownStatus = AccountBootstrapStatus(
        overall: .needsAttention("bootstrap_contract_unknown"),
        sourceKind: .newInstall,
        migrationID: nil,
        stages: AccountBootstrapStages(
            identity: .needsAttention,
            migration: .needsAttention,
            entitlement: .needsAttention,
            vault: .needsAttention
        ),
        lastErrorCode: "bootstrap_contract_unknown",
        retryCount: 0,
        updatedAt: Date(timeIntervalSince1970: 0)
    )

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct AccountBootstrapWireStages: Decodable {
    let identity: String
    let migration: String
    let entitlement: String
    let vault: String
}
