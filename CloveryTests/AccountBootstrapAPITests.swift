import Foundation
import XCTest
@testable import Clovery

@MainActor
final class AccountBootstrapAPITests: XCTestCase {
    override func tearDown() {
        BootstrapURLProtocolStub.reset()
        super.tearDown()
    }

    func testStatusAttachesBearerAndDecodesAllStageStates() async throws {
        let api = makeAPI(
            body: #"{"status":"running","source_kind":"legacy_local","migration_id":"11111111-1111-4111-8111-111111111111","stages":{"identity":"complete","migration":"pending","entitlement":"needs_attention","vault":"complete"},"last_error_code":"purchase_chain_conflict","retry_count":2,"updated_at":"2026-07-19T12:00:00Z"}"#
        )

        let status = try await api.status()

        XCTAssertEqual(BootstrapURLProtocolStub.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(BootstrapURLProtocolStub.lastRequest?.url?.path, "/v1/account/bootstrap")
        XCTAssertEqual(
            BootstrapURLProtocolStub.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer access"
        )
        XCTAssertEqual(status.overall, .running)
        XCTAssertEqual(status.stages.identity, .complete)
        XCTAssertEqual(status.stages.migration, .pending)
        XCTAssertEqual(status.stages.entitlement, .needsAttention)
        XCTAssertEqual(status.stages.vault, .complete)
        XCTAssertEqual(status.lastErrorCode, "purchase_chain_conflict")
    }

    func testResumeSendsSourceAndVaultCheckpointWithoutOwnershipFields() async throws {
        let api = makeAPI(body: Self.completeBody)

        _ = try await api.resume(
            sourceKind: .legacyCloudKit,
            vaultCheckpoint: VaultCheckpoint(cursor: 42, hasMore: false)
        )

        XCTAssertEqual(BootstrapURLProtocolStub.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(BootstrapURLProtocolStub.lastRequest?.url?.path, "/v1/account/bootstrap/resume")
        XCTAssertEqual(BootstrapURLProtocolStub.lastJSON?["source_kind"] as? String, "legacy_cloudkit")
        XCTAssertEqual(
            BootstrapURLProtocolStub.lastJSON?["vault_checkpoint"] as? [String: AnyHashable],
            ["cursor": 42, "has_more": false]
        )
        XCTAssertNil(BootstrapURLProtocolStub.lastJSON?["account_id"])
        XCTAssertNil(BootstrapURLProtocolStub.lastJSON?["vault_id"])
    }

    func testUnknownContractValuesBecomeNeedsAttention() async throws {
        let bodies = [
            #"{"status":"future","source_kind":"new_install","migration_id":null,"stages":{"identity":"complete","migration":"complete","entitlement":"complete","vault":"complete"},"last_error_code":null,"retry_count":0,"updated_at":"2026-07-19T12:00:00Z"}"#,
            #"{"status":"complete","source_kind":"new_install","migration_id":null,"stages":{"identity":"complete","migration":"future","entitlement":"complete","vault":"complete"},"last_error_code":null,"retry_count":0,"updated_at":"2026-07-19T12:00:00Z"}"#,
            #"{"status":"complete","source_kind":"new_install","migration_id":null,"stages":{"identity":"complete","migration":"pending","entitlement":"complete","vault":"complete"},"last_error_code":null,"retry_count":0,"updated_at":"2026-07-19T12:00:00Z"}"#
        ]

        for body in bodies {
            let status = try await makeAPI(body: body).status()
            XCTAssertEqual(status.overall, .needsAttention("bootstrap_contract_unknown"))
            XCTAssertNotEqual(status.overall, .complete)
        }
    }

    private func makeAPI(body: String) -> AccountBootstrapAPI {
        BootstrapURLProtocolStub.responseData = Data(body.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BootstrapURLProtocolStub.self]
        let baseClient = APIClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://api.test.invalid")!),
            session: URLSession(configuration: configuration)
        )
        let sessionController = BootstrapAuthenticatedSessionSpy()
        let authenticatedClient = AuthenticatedAPIClient(
            client: baseClient,
            sessionController: sessionController
        )
        return AccountBootstrapAPI(client: authenticatedClient)
    }

    private static let completeBody = #"{"status":"complete","source_kind":"new_install","migration_id":null,"stages":{"identity":"complete","migration":"complete","entitlement":"complete","vault":"complete"},"last_error_code":null,"retry_count":0,"updated_at":"2026-07-19T12:00:00Z"}"#
}

@MainActor
private final class BootstrapAuthenticatedSessionSpy: AuthenticatedSessionControlling {
    func authenticationSession() -> AuthenticationSession? {
        AuthenticationSession(
            accountID: "account",
            vaultID: "vault",
            accessToken: "access",
            accessTokenExpiresAt: Date().addingTimeInterval(900)
        )
    }

    func refreshAuthenticatedSession() async throws -> AuthenticationSession {
        try XCTUnwrap(authenticationSession())
    }

    func logout() {}
}

private final class BootstrapURLProtocolStub: URLProtocol {
    static var responseData = Data()
    static var lastRequest: URLRequest?
    static var lastJSON: [String: Any]?

    static func reset() {
        responseData = Data()
        lastRequest = nil
        lastJSON = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastJSON = request.capturedBodyData.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
