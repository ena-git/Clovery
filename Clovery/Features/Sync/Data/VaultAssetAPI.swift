import Foundation

struct VaultMigrationAsset: Codable, Equatable {
    let sourceFilename: String
    let assetID: UUID
    let byteSize: Int64
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case sourceFilename = "source_filename"
        case assetID = "asset_id"
        case byteSize = "byte_size"
        case sha256
    }
}

struct VaultAssetUploadRequest: Encodable, Equatable {
    let assetID: UUID
    let contentType: String
    let byteSize: Int64
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case contentType = "content_type"
        case byteSize = "byte_size"
        case sha256
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(assetID.uuidString.lowercased(), forKey: .assetID)
        try container.encode(contentType, forKey: .contentType)
        try container.encode(byteSize, forKey: .byteSize)
        try container.encode(sha256, forKey: .sha256)
    }
}

enum VaultAssetUploadStatus: String, Codable, Equatable {
    case uploadRequired = "upload_required"
    case complete
}

struct VaultAssetUploadTicket: Decodable, Equatable {
    let assetID: UUID
    let status: VaultAssetUploadStatus
    let uploadURL: URL?
    let requiredHeaders: [String: String]
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case status
        case uploadURL = "upload_url"
        case requiredHeaders = "required_headers"
        case expiresAt = "expires_at"
    }

    init(
        assetID: UUID,
        status: VaultAssetUploadStatus,
        uploadURL: URL?,
        requiredHeaders: [String: String],
        expiresAt: String?
    ) {
        self.assetID = assetID
        self.status = status
        self.uploadURL = uploadURL
        self.requiredHeaders = requiredHeaders
        self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assetID = try container.decode(UUID.self, forKey: .assetID)
        status = try container.decode(VaultAssetUploadStatus.self, forKey: .status)
        uploadURL = try container.decodeIfPresent(URL.self, forKey: .uploadURL)
        requiredHeaders = try container.decodeIfPresent([String: String].self, forKey: .requiredHeaders) ?? [:]
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt)
    }
}

struct VaultAssetDownloadTicket: Decodable, Equatable {
    let assetID: UUID
    let downloadURL: URL
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case downloadURL = "download_url"
        case expiresAt = "expires_at"
    }


    init(assetID: UUID, downloadURL: URL, expiresAt: String) {
        self.assetID = assetID
        self.downloadURL = downloadURL
        self.expiresAt = expiresAt
    }
}

@MainActor
protocol VaultAssetAPIProtocol: AnyObject {
    func listMigrationAssets(migrationID: UUID) async throws -> [VaultMigrationAsset]
    func startUpload(_ request: VaultAssetUploadRequest) async throws -> VaultAssetUploadTicket
    func upload(_ data: Data, using ticket: VaultAssetUploadTicket) async throws
    func complete(assetID: UUID) async throws
    func downloadTicket(assetID: UUID) async throws -> VaultAssetDownloadTicket
    func download(using ticket: VaultAssetDownloadTicket) async throws -> Data
}

@MainActor
final class VaultAssetAPI: VaultAssetAPIProtocol {
    private let client: AuthenticatedAPIClient
    private let objectSession: URLSession
    private let encoder: JSONEncoder

    init(
        client: AuthenticatedAPIClient,
        objectSession: URLSession = .shared,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.client = client
        self.objectSession = objectSession
        self.encoder = encoder
    }

    func listMigrationAssets(migrationID: UUID) async throws -> [VaultMigrationAsset] {
        let response: MigrationAssetList = try await client.send(
            APIRequest(
                method: "GET",
                path: "/v1/vault/migrations/\(migrationID.uuidString.lowercased())/assets"
            ),
            decoding: MigrationAssetList.self
        )
        return response.assets
    }

    func startUpload(_ request: VaultAssetUploadRequest) async throws -> VaultAssetUploadTicket {
        try await client.send(
            APIRequest(
                method: "POST",
                path: "/v1/vault/assets/uploads",
                body: try encoder.encode(request),
                stableRequestID: "vault-asset-\(request.assetID.uuidString.lowercased())"
            ),
            decoding: VaultAssetUploadTicket.self
        )
    }

    func upload(_ data: Data, using ticket: VaultAssetUploadTicket) async throws {
        guard ticket.status == .uploadRequired, let uploadURL = ticket.uploadURL else {
            if ticket.status == .complete { return }
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.httpBody = data
        ticket.requiredHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        _ = try await performObjectRequest(request)
    }

    func complete(assetID: UUID) async throws {
        try await client.sendWithoutResponse(
            APIRequest(
                method: "POST",
                path: "/v1/vault/assets/\(assetID.uuidString.lowercased())/complete",
                stableRequestID: "vault-asset-complete-\(assetID.uuidString.lowercased())"
            )
        )
    }

    func downloadTicket(assetID: UUID) async throws -> VaultAssetDownloadTicket {
        try await client.send(
            APIRequest(
                method: "GET",
                path: "/v1/vault/assets/\(assetID.uuidString.lowercased())/download"
            ),
            decoding: VaultAssetDownloadTicket.self
        )
    }

    func download(using ticket: VaultAssetDownloadTicket) async throws -> Data {
        try await performObjectRequest(URLRequest(url: ticket.downloadURL))
    }

    private func performObjectRequest(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await objectSession.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.server(
                code: "object_http_\(response.statusCode)",
                message: "The vault asset transfer failed.",
                statusCode: response.statusCode
            )
        }
        return data
    }
}

private struct MigrationAssetList: Decodable {
    let assets: [VaultMigrationAsset]
}
