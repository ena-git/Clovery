import Foundation
import XCTest
@testable import Clovery

@MainActor
final class AccountEntitlementAPITests: XCTestCase {
    override func tearDown() {
        EntitlementURLProtocolStub.reset()
        super.tearDown()
    }

    func testBillingEndpointsSendExactAuthenticatedContracts() async throws {
        EntitlementURLProtocolStub.handler = { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/v1/billing/apple/legacy-claims"),
                 ("POST", "/v1/billing/apple/transactions/verify"):
                return Self.response(status: 200, body: Self.activeEntitlementJSON)
            case ("POST", "/v1/billing/apple/restore"),
                 ("GET", "/v1/account/entitlements"):
                return Self.response(
                    status: 200,
                    body: #"{"entitlements":[\#(Self.activeEntitlementJSON)]}"#
                )
            default:
                return Self.response(status: 404)
            }
        }
        let api = makeAPI()

        _ = try await api.claimLegacy(
            signedTransactionInfo: "header.payload.signature",
            environment: .production
        )
        _ = try await api.verify(transactionID: 42, environment: .sandbox)
        _ = try await api.restore(transactionIDs: [42, 84], environment: .production)
        let listed = try await api.list()

        XCTAssertEqual(listed.map(\.productID), [BoardStore.productID])
        let requests = EntitlementURLProtocolStub.requests
        XCTAssertEqual(
            requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" },
            [
                "POST /v1/billing/apple/legacy-claims",
                "POST /v1/billing/apple/transactions/verify",
                "POST /v1/billing/apple/restore",
                "GET /v1/account/entitlements",
            ]
        )
        requests.forEach {
            XCTAssertEqual(
                $0.value(forHTTPHeaderField: "Authorization"),
                "Bearer entitlement-access"
            )
        }

        XCTAssertEqual(
            try json(requests[0]),
            [
                "signed_transaction_info": "header.payload.signature",
                "environment": "production",
            ]
        )
        XCTAssertEqual(
            try json(requests[1]),
            ["transaction_id": "42", "environment": "sandbox"]
        )
        XCTAssertEqual(
            try json(requests[2]),
            ["transaction_ids": ["42", "84"], "environment": "production"]
        )

        for request in requests {
            let body = request.capturedBodyData.flatMap {
                String(data: $0, encoding: .utf8)
            } ?? ""
            XCTAssertFalse(body.contains("apple_subject"))
            XCTAssertFalse(body.contains("apple_email"))
            XCTAssertFalse(body.contains("account_id"))
        }
    }

    func testServerBillingErrorsRemainTypedForReconciliation() async throws {
        let cases = [
            (409, "apple_transaction_claimed"),
            (503, "apple_verification_unavailable"),
        ]

        for testCase in cases {
            EntitlementURLProtocolStub.reset()
            EntitlementURLProtocolStub.handler = { _ in
                Self.response(
                    status: testCase.0,
                    body: #"{"code":"\#(testCase.1)","message":"Billing failed."}"#
                )
            }

            do {
                _ = try await makeAPI().verify(transactionID: 42, environment: .production)
                XCTFail("Expected server error \(testCase.1)")
            } catch let error as APIError {
                XCTAssertEqual(error.code, testCase.1)
                XCTAssertEqual(error.statusCode, testCase.0)
            }
        }
    }

    private func makeAPI() -> AccountEntitlementAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EntitlementURLProtocolStub.self]
        let baseClient = APIClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://api.example")!),
            session: URLSession(configuration: configuration)
        )
        let authenticatedClient = AuthenticatedAPIClient(
            client: baseClient,
            sessionController: EntitlementSessionControllerSpy()
        )
        return AccountEntitlementAPI(client: authenticatedClient)
    }

    private func json(_ request: URLRequest) throws -> [String: AnyHashable] {
        let object = try JSONSerialization.jsonObject(
            with: try XCTUnwrap(request.capturedBodyData)
        )
        return try XCTUnwrap(object as? [String: AnyHashable])
    }

    nonisolated private static func response(
        status: Int,
        body: String = ""
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

    nonisolated private static let activeEntitlementJSON = #"{"product_id":"com.clovery.app.board.lifetime","state":"active","source_storefront":"CN","source_transaction_id":"42","updated_at":"2026-07-27T00:00:00Z"}"#
}

@MainActor
private final class EntitlementSessionControllerSpy: AuthenticatedSessionControlling {
    func authenticationSession() -> AuthenticationSession? {
        AuthenticationSession(
            accountID: "11111111-1111-4111-8111-111111111111",
            vaultID: "22222222-2222-4222-8222-222222222222",
            accessToken: "entitlement-access",
            accessTokenExpiresAt: Date().addingTimeInterval(900)
        )
    }

    func refreshAuthenticatedSession() async throws -> AuthenticationSession {
        try XCTUnwrap(authenticationSession())
    }

    func logout() {}
}

private final class EntitlementURLProtocolStub: URLProtocol {
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
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil
            )!,
            Data()
        )
        client?.urlProtocol(self, didReceive: response.0, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
