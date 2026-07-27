import CryptoKit
import Foundation
import XCTest
@testable import Clovery

@MainActor
final class LegacyMigrationAPITests: XCTestCase {
    override func setUp() {
        super.setUp()
        MigrationURLProtocolStub.reset()
    }

    func testMigrationAndObjectUploadHTTPContract() async throws {
        let migrationID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let assetID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let manifestData = Data(#"{"format_version":1}"#.utf8)
        let manifestSHA = sha256(manifestData)
        MigrationURLProtocolStub.handler = { request in
            switch (request.httpMethod, request.url?.host, request.url?.path) {
            case ("POST", _, "/v1/vault/migrations"):
                return Self.response(
                    status: 201,
                    body: #"{"migration_id":"11111111-1111-4111-8111-111111111111","format_version":1,"source":"v1_bundle","entry_count":1,"deleted_count":1,"asset_count":1,"total_bytes":15,"manifest_sha256":"\#(manifestSHA)","status":"uploading","created_at":"2026-07-27T00:00:00Z"}"#
                )
            case ("POST", _, "/v1/vault/migrations/\(migrationID.uuidString.lowercased())/entries"):
                return Self.response(status: 204)
            case ("POST", _, "/v1/vault/migrations/\(migrationID.uuidString.lowercased())/assets"):
                return Self.response(
                    status: 201,
                    body: #"{"asset_id":"\#(assetID.uuidString.lowercased())","status":"upload_required","upload_url":"https://uploads.example/object","required_headers":{"Content-Type":"image/jpeg","X-Amz-Meta-Sha256":"photo-sha","If-None-Match":"*"},"expires_at":"2026-07-27T00:15:00Z"}"#
                )
            case ("PUT", "uploads.example", "/object"):
                return Self.response(status: 200)
            case ("POST", _, "/v1/vault/assets/\(assetID.uuidString.lowercased())/complete"):
                return Self.response(status: 204)
            case ("POST", _, "/v1/vault/migrations/\(migrationID.uuidString.lowercased())/verify"),
                 ("GET", _, "/v1/vault/migrations/\(migrationID.uuidString.lowercased())/report"):
                return Self.response(status: 200, body: Self.verifiedReportJSON)
            default:
                return Self.response(status: 404)
            }
        }
        let api = makeAPI()

        _ = try await api.create(
            LegacyMigrationCreateRequest(
                migrationID: migrationID,
                formatVersion: 1,
                source: "v1_bundle",
                entryCount: 1,
                assetCount: 1,
                totalBytes: 15,
                manifestSHA256: manifestSHA,
                manifestBase64: manifestData.base64EncodedString()
            )
        )
        try await api.addEntry(
            migrationID: migrationID,
            entry: LegacyMigrationEntryUpload(
                entryID: "entry-1",
                payload: Data(#"{"id":"entry-1","text":"hello"}"#.utf8),
                sha256: "entry-sha",
                deletedAt: nil
            )
        )
        try await api.addEntry(
            migrationID: migrationID,
            entry: LegacyMigrationEntryUpload(
                entryID: "deleted-1",
                payload: Data("{}".utf8),
                sha256: "deleted-sha",
                deletedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        let ticket = try await api.addAsset(
            migrationID: migrationID,
            asset: LegacyMigrationAssetUpload(
                assetID: assetID,
                sourceFilename: "photo-1.jpg",
                contentType: "image/jpeg",
                byteSize: 3,
                sha256: "photo-sha"
            )
        )
        try await api.uploadAsset(Data([1, 2, 3]), using: ticket)
        try await api.completeAsset(assetID: assetID)
        _ = try await api.verify(migrationID: migrationID)
        _ = try await api.report(migrationID: migrationID)

        let requests = MigrationURLProtocolStub.requests
        XCTAssertEqual(
            requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" },
            [
                "POST /v1/vault/migrations",
                "POST /v1/vault/migrations/\(migrationID.uuidString.lowercased())/entries",
                "POST /v1/vault/migrations/\(migrationID.uuidString.lowercased())/entries",
                "POST /v1/vault/migrations/\(migrationID.uuidString.lowercased())/assets",
                "PUT /object",
                "POST /v1/vault/assets/\(assetID.uuidString.lowercased())/complete",
                "POST /v1/vault/migrations/\(migrationID.uuidString.lowercased())/verify",
                "GET /v1/vault/migrations/\(migrationID.uuidString.lowercased())/report",
            ]
        )
        let createJSON = try json(requests[0])
        XCTAssertEqual(createJSON["manifest_base64"] as? String, manifestData.base64EncodedString())
        XCTAssertEqual(createJSON["manifest_sha256"] as? String, manifestSHA)
        let activeJSON = try json(requests[1])
        XCTAssertEqual((activeJSON["payload"] as? [String: Any])?["text"] as? String, "hello")
        let deletedJSON = try json(requests[2])
        XCTAssertEqual(deletedJSON["payload"] as? [String: AnyHashable], [:])
        XCTAssertNotNil(deletedJSON["deleted_at"])

        let objectRequest = requests[4]
        XCTAssertNil(objectRequest.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(objectRequest.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
        XCTAssertEqual(objectRequest.value(forHTTPHeaderField: "If-None-Match"), "*")
        XCTAssertEqual(objectRequest.capturedBodyData, Data([1, 2, 3]))
    }

    private func makeAPI() -> LegacyMigrationAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MigrationURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://api.example")!),
            session: session
        )
        let authenticated = AuthenticatedAPIClient(
            client: client,
            sessionController: MigrationSessionControllerSpy()
        )
        return LegacyMigrationAPI(
            client: authenticated,
            uploadSession: session
        )
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.capturedBodyData))
                as? [String: Any]
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func response(status: Int, body: String = "") -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: URL(string: "https://api.example")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data(body.utf8)
        )
    }

    private static let verifiedReportJSON = #"{"migration_id":"11111111-1111-4111-8111-111111111111","status":"verified","expected_entries":1,"imported_entries":1,"inserted_entries":0,"duplicate_entries":1,"conflict_copies":0,"expected_deleted_entries":1,"imported_deleted_entries":1,"expected_assets":1,"verified_assets":1,"expected_bytes":15,"verified_bytes":15,"errors":[],"verified_at":"2026-07-27T00:00:00Z"}"#
}

@MainActor
private final class MigrationSessionControllerSpy: AuthenticatedSessionControlling {
    func authenticationSession() -> AuthenticationSession? {
        AuthenticationSession(
            accountID: "account",
            vaultID: "vault",
            accessToken: "access-token",
            accessTokenExpiresAt: Date().addingTimeInterval(900)
        )
    }

    func refreshAuthenticatedSession() async throws -> AuthenticationSession {
        try XCTUnwrap(authenticationSession())
    }

    func logout() {}
}

private final class MigrationURLProtocolStub: URLProtocol {
    static var requests: [URLRequest] = []
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    static func reset() {
        requests = []
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let response = Self.handler?(request) ?? (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!,
            Data()
        )
        client?.urlProtocol(self, didReceive: response.0, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
