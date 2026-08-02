import Foundation
import XCTest
@testable import Clovery

final class IdentityClaimAPITests: XCTestCase {
    override func tearDown() {
        IdentityClaimURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testRegisterSendsBoundIdentityClaimWithoutPersistingAccountFields() async throws {
        let session = AuthSessionResponse(
            accountID: "account",
            vaultID: "vault",
            accessToken: "access",
            accessTokenExpiresIn: 900,
            refreshToken: "refresh",
            recoveryCodes: nil
        )
        IdentityClaimURLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 201, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, try JSONEncoder().encode(session))
        }
        let api = makeAPI()
        let registrationRequestID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let claim = IdentityClaimContext(
            provider: .apple,
            token: "claim-secret",
            expiresAt: Date().addingTimeInterval(300)
        )

        let result = try await api.register(
            loginID: "clovery_user",
            password: "eight888",
            claim: claim,
            registrationRequestID: registrationRequestID,
            sourceKind: .legacyLocal,
            device: DeviceRegistration(deviceID: "device", platform: "ios", displayName: "Test iPhone")
        )

        XCTAssertEqual(result.accountID, "account")
        XCTAssertEqual(IdentityClaimURLProtocolStub.lastRequest?.url?.path, "/v1/auth/accounts")
        XCTAssertEqual(IdentityClaimURLProtocolStub.lastJSON?["recovery_method"] as? String, "bound_identity")
        XCTAssertEqual(IdentityClaimURLProtocolStub.lastJSON?["identity_claim_token"] as? String, "claim-secret")
        XCTAssertEqual(IdentityClaimURLProtocolStub.lastJSON?["registration_request_id"] as? String, registrationRequestID.uuidString.lowercased())
        XCTAssertEqual(IdentityClaimURLProtocolStub.lastJSON?["source_kind"] as? String, "legacy_local")
        XCTAssertNil(IdentityClaimURLProtocolStub.lastJSON?["account_id"])
        XCTAssertNil(IdentityClaimURLProtocolStub.lastJSON?["vault_id"])
    }

    private func makeAPI() -> IdentityClaimAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [IdentityClaimURLProtocolStub.self]
        let client = APIClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://api.test.invalid")!),
            session: URLSession(configuration: configuration)
        )
        return IdentityClaimAPI(client: client)
    }
}

private final class IdentityClaimURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var lastRequest: URLRequest?
    static var lastJSON: [String: Any]?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastJSON = request.capturedBodyData.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
