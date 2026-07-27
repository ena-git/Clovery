import Foundation

@MainActor
protocol LegacyMigrationAPIProtocol: AnyObject {
    func create(_ request: LegacyMigrationCreateRequest) async throws -> LegacyMigrationRemote
    func addEntry(migrationID: UUID, entry: LegacyMigrationEntryUpload) async throws
    func addAsset(
        migrationID: UUID,
        asset: LegacyMigrationAssetUpload
    ) async throws -> LegacyAssetUploadTicket
    func uploadAsset(_ data: Data, using ticket: LegacyAssetUploadTicket) async throws
    func completeAsset(assetID: UUID) async throws
    func verify(migrationID: UUID) async throws -> LegacyMigrationReport
    func report(migrationID: UUID) async throws -> LegacyMigrationReport
}

@MainActor
final class LegacyMigrationAPI: LegacyMigrationAPIProtocol {
    private let client: AuthenticatedAPIClient
    private let uploadSession: URLSession
    private let encoder: JSONEncoder

    init(
        client: AuthenticatedAPIClient,
        uploadSession: URLSession? = nil
    ) {
        self.client = client
        self.uploadSession = uploadSession ?? Self.makeUploadSession()
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func create(
        _ request: LegacyMigrationCreateRequest
    ) async throws -> LegacyMigrationRemote {
        try await client.send(
            APIRequest(
                method: "POST",
                path: "/v1/vault/migrations",
                body: try encoder.encode(request),
                stableRequestID: "migration-create-\(request.migrationID.uuidString.lowercased())"
            ),
            decoding: LegacyMigrationRemote.self
        )
    }

    func addEntry(
        migrationID: UUID,
        entry: LegacyMigrationEntryUpload
    ) async throws {
        let payload = try JSONSerialization.jsonObject(with: entry.payload)
        var body: [String: Any] = [
            "entry_id": entry.entryID,
            "payload": payload,
            "sha256": entry.sha256,
        ]
        if let deletedAt = entry.deletedAt {
            body["deleted_at"] = Self.dateString(deletedAt)
        }
        try await client.sendWithoutResponse(
            APIRequest(
                method: "POST",
                path: "/v1/vault/migrations/\(migrationID.uuidString.lowercased())/entries",
                body: try JSONSerialization.data(
                    withJSONObject: body,
                    options: [.sortedKeys, .withoutEscapingSlashes]
                ),
                stableRequestID: "migration-entry-\(migrationID)-\(entry.entryID)"
            )
        )
    }

    func addAsset(
        migrationID: UUID,
        asset: LegacyMigrationAssetUpload
    ) async throws -> LegacyAssetUploadTicket {
        try await client.send(
            APIRequest(
                method: "POST",
                path: "/v1/vault/migrations/\(migrationID.uuidString.lowercased())/assets",
                body: try encoder.encode(LegacyMigrationAssetRequest(asset)),
                stableRequestID: "migration-asset-\(migrationID)-\(asset.sourceFilename)"
            ),
            decoding: LegacyAssetUploadTicket.self
        )
    }

    func uploadAsset(
        _ data: Data,
        using ticket: LegacyAssetUploadTicket
    ) async throws {
        guard ticket.status == .uploadRequired,
              let uploadURL = ticket.uploadURL else {
            throw LegacyMigrationAPIError.invalidUploadTicket
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.httpBody = data
        for (name, value) in ticket.requiredHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (_, response) = try await uploadSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw LegacyMigrationAPIError.objectUploadFailed
        }
    }

    func completeAsset(assetID: UUID) async throws {
        try await client.sendWithoutResponse(
            APIRequest(
                method: "POST",
                path: "/v1/vault/assets/\(assetID.uuidString.lowercased())/complete",
                stableRequestID: "migration-asset-complete-\(assetID.uuidString.lowercased())"
            )
        )
    }

    func verify(migrationID: UUID) async throws -> LegacyMigrationReport {
        try await client.send(
            APIRequest(
                method: "POST",
                path: "/v1/vault/migrations/\(migrationID.uuidString.lowercased())/verify",
                stableRequestID: "migration-verify-\(migrationID.uuidString.lowercased())"
            ),
            decoding: LegacyMigrationReport.self
        )
    }

    func report(migrationID: UUID) async throws -> LegacyMigrationReport {
        try await client.send(
            APIRequest(
                method: "GET",
                path: "/v1/vault/migrations/\(migrationID.uuidString.lowercased())/report"
            ),
            decoding: LegacyMigrationReport.self
        )
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func makeUploadSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpAdditionalHeaders = [:]
        return URLSession(configuration: configuration)
    }
}

private struct LegacyMigrationAssetRequest: Encodable {
    let assetID: String
    let sourceFilename: String
    let contentType: String
    let byteSize: Int64
    let sha256: String

    init(_ upload: LegacyMigrationAssetUpload) {
        assetID = upload.assetID.uuidString.lowercased()
        sourceFilename = upload.sourceFilename
        contentType = upload.contentType
        byteSize = upload.byteSize
        sha256 = upload.sha256
    }

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case sourceFilename = "source_filename"
        case contentType = "content_type"
        case byteSize = "byte_size"
        case sha256
    }
}

private enum LegacyMigrationAPIError: Error {
    case invalidUploadTicket
    case objectUploadFailed
}
