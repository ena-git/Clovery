import Foundation
import XCTest
@testable import Clovery

@MainActor
final class VaultAssetAPITests: XCTestCase {
    override func tearDown() {
        VaultAPIURLProtocolStub.reset()
        super.tearDown()
    }

    func testMigrationMappingAndUploadDownloadTicketsKeepBearerOffObjectURLs() async throws {
        let migrationID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let assetID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        VaultAPIURLProtocolStub.handler = { request in
            switch (request.httpMethod, request.url?.host, request.url?.path) {
            case ("GET", _, "/v1/vault/migrations/\(migrationID.uuidString.lowercased())/assets"):
                return Self.response(status: 200, body: #"{"assets":[{"source_filename":"photo-1.jpg","asset_id":"22222222-2222-4222-8222-222222222222","byte_size":3,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}"#)
            case ("POST", _, "/v1/vault/assets/uploads"):
                return Self.response(status: 201, body: #"{"asset_id":"22222222-2222-4222-8222-222222222222","status":"upload_required","upload_url":"https://objects.example/upload","required_headers":{"Content-Type":"image/jpeg","If-None-Match":"*"},"expires_at":"2026-07-27T00:15:00Z"}"#)
            case ("PUT", "objects.example", "/upload"):
                return Self.response(status: 200, body: "")
            case ("POST", _, "/v1/vault/assets/\(assetID.uuidString.lowercased())/complete"):
                return Self.response(status: 204, body: "")
            case ("GET", _, "/v1/vault/assets/\(assetID.uuidString.lowercased())/download"):
                return Self.response(status: 200, body: #"{"asset_id":"22222222-2222-4222-8222-222222222222","download_url":"https://objects.example/download","expires_at":"2026-07-27T00:15:00Z"}"#)
            case ("GET", "objects.example", "/download"):
                return Self.response(status: 200, body: "abc")
            default:
                return Self.response(status: 404, body: "")
            }
        }
        let api = VaultAssetAPI(
            client: makeVaultAuthenticatedClient(),
            objectSession: makeVaultURLSession()
        )

        let mappings = try await api.listMigrationAssets(migrationID: migrationID)
        let upload = try await api.startUpload(
            VaultAssetUploadRequest(
                assetID: assetID,
                contentType: "image/jpeg",
                byteSize: 3,
                sha256: String(repeating: "a", count: 64)
            )
        )
        try await api.upload(Data("abc".utf8), using: upload)
        try await api.complete(assetID: assetID)
        let download = try await api.downloadTicket(assetID: assetID)
        let bytes = try await api.download(using: download)

        XCTAssertEqual(mappings.first?.sourceFilename, "photo-1.jpg")
        XCTAssertEqual(bytes, Data("abc".utf8))
        let requests = VaultAPIURLProtocolStub.requests
        let objectRequests = requests.filter { $0.url?.host == "objects.example" }
        XCTAssertEqual(objectRequests.count, 2)
        objectRequests.forEach {
            XCTAssertNil($0.value(forHTTPHeaderField: "Authorization"))
        }
        XCTAssertEqual(objectRequests.first?.value(forHTTPHeaderField: "If-None-Match"), "*")
        XCTAssertEqual(objectRequests.first?.capturedBodyData, Data("abc".utf8))
    }

    nonisolated private static func response(
        status: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: URL(string: "https://api.example")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }
}

