import Foundation
import XCTest
@testable import Clovery

@MainActor
final class AccountManagementAPITests: XCTestCase {
    override func tearDown() {
        AccountManagementURLProtocolStub.reset()
        super.tearDown()
    }

    func testSummaryUsesAuthenticatedAccountRouteAndExposesProviderWithoutIssuer() async throws {
        let api = makeAPI(
            body: #"{"account_id":"11111111-1111-4111-8111-111111111111","clovery_id":"garden_user","status":"active","created_at":"2026-07-19T12:00:00Z","has_password":true,"passkey_count":1,"recovery_codes_remaining":6,"bindings":[{"provider":"apple","issuer":"https://appleid.apple.com","created_at":"2026-07-19T12:00:00Z"}]}"#
        )

        let summary = try await api.summary()

        XCTAssertEqual(AccountManagementURLProtocolStub.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(AccountManagementURLProtocolStub.lastRequest?.url?.path, "/v1/account")
        XCTAssertEqual(
            AccountManagementURLProtocolStub.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer access"
        )
        XCTAssertEqual(summary.cloveryID, "garden_user")
        XCTAssertEqual(summary.bindings, [AccountBinding(provider: .apple)])
    }

    func testDeletionRequestUsesAuthenticatedBodylessAccountRoute() async throws {
        let api = makeAPI(
            body: #"{"request_id":"22222222-2222-4222-8222-222222222222","status":"pending","requested_at":"2026-07-19T12:00:00Z","scheduled_for":"2026-08-18T12:00:00Z"}"#
        )

        let request = try await api.requestDeletion()

        XCTAssertEqual(AccountManagementURLProtocolStub.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(
            AccountManagementURLProtocolStub.lastRequest?.url?.path,
            "/v1/account/deletion-requests"
        )
        XCTAssertNil(AccountManagementURLProtocolStub.lastRequest?.httpBody)
        XCTAssertEqual(request.status, .pending)
        XCTAssertEqual(
            request.requestID,
            UUID(uuidString: "22222222-2222-4222-8222-222222222222")
        )
    }

    func testInvalidAccountContractFailsWithoutReturningRawPayload() async {
        let rawSecret = "issuer-subject-secret"
        let api = makeAPI(
            body: "{\"account_id\":\"11111111-1111-4111-8111-111111111111\",\"clovery_id\":\"garden_user\",\"status\":\"active\",\"created_at\":\"2026-07-19T12:00:00Z\",\"has_password\":true,\"passkey_count\":0,\"recovery_codes_remaining\":0,\"bindings\":[{\"provider\":\"apple\",\"issuer\":\"https://appleid.apple.com\",\"created_at\":\"2026-07-19T12:00:00Z\",\"subject\":\"\(rawSecret)\"}]}"
        )

        do {
            _ = try await api.summary()
            XCTFail("invalid contract must fail")
        } catch {
            XCTAssertFalse(String(describing: error).contains(rawSecret))
        }
    }

    func testSummaryAcceptsEveryProviderAllowedByBackendContract() async throws {
        let api = makeAPI(
            body: #"{"account_id":"11111111-1111-4111-8111-111111111111","clovery_id":"garden_user","status":"active","created_at":"2026-07-19T12:00:00Z","has_password":true,"passkey_count":0,"recovery_codes_remaining":0,"bindings":[{"provider":"wechat","issuer":"wechat","created_at":"2026-07-19T12:00:00Z"},{"provider":"qq","issuer":"qq","created_at":"2026-07-19T12:00:00Z"}]}"#
        )

        let summary = try await api.summary()

        XCTAssertEqual(
            summary.bindings,
            [AccountBinding(provider: .wechat), AccountBinding(provider: .qq)]
        )
    }

    func testDeletionRequestRejectsNonFutureSchedule() async {
        let api = makeAPI(
            body: #"{"request_id":"22222222-2222-4222-8222-222222222222","status":"pending","requested_at":"2026-07-19T12:00:00Z","scheduled_for":"2026-07-19T12:00:00Z"}"#
        )

        do {
            _ = try await api.requestDeletion()
            XCTFail("non-future deletion schedule must fail")
        } catch {
            XCTAssertEqual(error as? APIError, .decoding("The account deletion response is invalid."))
        }
    }

    private func makeAPI(body: String) -> AccountManagementAPI {
        AccountManagementURLProtocolStub.responseData = Data(body.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountManagementURLProtocolStub.self]
        let baseClient = APIClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://api.test.invalid")!),
            session: URLSession(configuration: configuration)
        )
        return AccountManagementAPI(
            client: AuthenticatedAPIClient(
                client: baseClient,
                sessionController: AccountManagementSessionSpy()
            )
        )
    }
}

@MainActor
private final class AccountManagementSessionSpy: AuthenticatedSessionControlling {
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

private final class AccountManagementURLProtocolStub: URLProtocol {
    static var responseData = Data()
    static var statusCode = 200
    static var lastRequest: URLRequest?

    static func reset() {
        responseData = Data()
        statusCode = 200
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
