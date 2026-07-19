import Foundation
import XCTest
@testable import Clovery

final class AuthenticationAPIClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testRegisterSendsRecoveryCodesAndDevice() async throws {
        let response = AuthSessionResponse(
            accountID: "account",
            vaultID: "vault",
            accessToken: "access",
            accessTokenExpiresIn: 900,
            refreshToken: "refresh",
            recoveryCodes: ["one", "two"]
        )
        let api = makeAPI(response: response)
        let device = DeviceRegistration(
            deviceID: "device",
            platform: "ios",
            displayName: "Test iPhone"
        )

        let result = try await api.register(
            loginID: "clovery_user",
            password: "eight888",
            device: device
        )

        XCTAssertEqual(result.vaultID, "vault")
        XCTAssertEqual(URLProtocolStub.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(URLProtocolStub.lastRequest?.url?.path, "/v1/auth/accounts")
        XCTAssertEqual(URLProtocolStub.lastJSON?["login_id"] as? String, "clovery_user")
        XCTAssertEqual(URLProtocolStub.lastJSON?["recovery_method"] as? String, "recovery_codes")
        XCTAssertEqual(
            URLProtocolStub.lastJSON?["device"] as? [String: String],
            [
                "device_id": "device",
                "platform": "ios",
                "display_name": "Test iPhone"
            ]
        )
    }

    func testPasswordLoginSendsBearerlessCredentials() async throws {
        let api = makeAPI(response: makeSession())
        let device = DeviceRegistration(
            deviceID: "device",
            platform: "ios",
            displayName: "Test iPhone"
        )

        _ = try await api.login(
            loginID: "clovery_user",
            password: "eight888",
            device: device
        )

        XCTAssertEqual(URLProtocolStub.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(URLProtocolStub.lastRequest?.url?.path, "/v1/auth/password/login")
        XCTAssertNil(URLProtocolStub.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testRefreshSendsOnlyRefreshTokenAndDecodesRotatedSession() async throws {
        let api = makeAPI(response: makeSession(refreshToken: "rotated"))

        let result = try await api.refresh(refreshToken: "old-refresh")

        XCTAssertEqual(result.refreshToken, "rotated")
        XCTAssertEqual(URLProtocolStub.lastRequest?.url?.path, "/v1/auth/sessions/refresh")
        XCTAssertNil(URLProtocolStub.lastRequest?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(URLProtocolStub.lastJSON?["refresh_token"] as? String, "old-refresh")
    }

    func testFederatedStartPreservesProviderAndDecodesNonce() async throws {
        URLProtocolStub.responseData = try JSONEncoder().encode(
            FederationIntentResponse(
                intentID: "intent",
                provider: "apple",
                nonce: "nonce",
                expiresIn: 300
            )
        )
        let api = makeAPI(response: makeSession())

        let result = try await api.startFederatedLogin(provider: .apple)

        XCTAssertEqual(result.intentID, "intent")
        XCTAssertEqual(result.nonce, "nonce")
        XCTAssertEqual(URLProtocolStub.lastRequest?.url?.path, "/v1/auth/federated/apple/start")
    }

    func testFederatedCompletePreservesIntentNonceAndAuthorizationCode() async throws {
        let api = makeAPI(response: makeSession())

        _ = try await api.completeFederatedLogin(
            provider: .apple,
            intentID: "server-intent",
            nonce: "server-nonce",
            authorizationCode: "provider-code",
            device: DeviceRegistration(
                deviceID: "device",
                platform: "ios",
                displayName: "Test iPhone"
            )
        )

        XCTAssertEqual(URLProtocolStub.lastRequest?.url?.path, "/v1/auth/federated/apple/complete")
        XCTAssertEqual(URLProtocolStub.lastJSON?["intent_id"] as? String, "server-intent")
        XCTAssertEqual(URLProtocolStub.lastJSON?["nonce"] as? String, "server-nonce")
        XCTAssertEqual(URLProtocolStub.lastJSON?["authorization_code"] as? String, "provider-code")
    }

    func testRecoveryCodeResetConsumesCodeThenAcceptsNoContentCompletion() async throws {
        let api = makeAPI(response: makeSession())
        URLProtocolStub.responseData = try JSONEncoder().encode(
            RecoveryProofResponse(
                resetIntentID: "reset-intent",
                recoveryProof: "reset-proof",
                expiresIn: 600
            )
        )

        let proof = try await api.consumeRecoveryCode(
            loginID: "clovery_user",
            recoveryCode: "one-time-code"
        )

        XCTAssertEqual(proof.recoveryProof, "reset-proof")
        XCTAssertEqual(URLProtocolStub.lastRequest?.url?.path, "/v1/auth/recovery-codes/consume")
        XCTAssertEqual(URLProtocolStub.lastJSON?["login_id"] as? String, "clovery_user")
        XCTAssertEqual(URLProtocolStub.lastJSON?["recovery_code"] as? String, "one-time-code")

        URLProtocolStub.statusCode = 204
        URLProtocolStub.responseData = Data()

        try await api.completePasswordReset(
            resetIntentID: proof.resetIntentID,
            proof: proof.recoveryProof,
            newPassword: "eight888"
        )

        XCTAssertEqual(URLProtocolStub.lastRequest?.url?.path, "/v1/auth/password/reset/complete")
        XCTAssertEqual(URLProtocolStub.lastJSON?["reset_intent_id"] as? String, "reset-intent")
        XCTAssertEqual(URLProtocolStub.lastJSON?["proof"] as? String, "reset-proof")
        XCTAssertEqual(URLProtocolStub.lastJSON?["new_password"] as? String, "eight888")
    }

    func testAPIErrorEnvelopeMapsToTypedError() async throws {
        URLProtocolStub.statusCode = 401
        URLProtocolStub.responseData = Data(#"{"code":"invalid_credentials","message":"Authentication failed."}"#.utf8)
        let api = makeAPI(response: makeSession())

        do {
            _ = try await api.login(
                loginID: "clovery_user",
                password: "eight888",
                device: DeviceRegistration(
                    deviceID: "device",
                    platform: "ios",
                    displayName: "Test iPhone"
                )
            )
            XCTFail("login should fail")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "invalid_credentials")
            XCTAssertEqual(error.statusCode, 401)
        }
    }

    private func makeAPI(response: AuthSessionResponse) -> AuthenticationAPI {
        URLProtocolStub.statusCode = 200
        URLProtocolStub.responseData = try! JSONEncoder().encode(response)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let client = APIClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://api.test.invalid")!),
            session: session
        )
        return AuthenticationAPI(client: client)
    }

    private func makeSession(refreshToken: String = "refresh") -> AuthSessionResponse {
        AuthSessionResponse(
            accountID: "account",
            vaultID: "vault",
            accessToken: "access",
            accessTokenExpiresIn: 900,
            refreshToken: refreshToken,
            recoveryCodes: nil
        )
    }
}

private final class URLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var responseData = Data()
    static var statusCode = 200
    static var lastRequest: URLRequest?
    static var lastJSON: [String: Any]?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lastRequest = request
        if let body = request.httpBody {
            Self.lastJSON = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        } else {
            Self.lastJSON = nil
        }

        do {
            let response: HTTPURLResponse
            let data: Data
            if let requestHandler = Self.requestHandler {
                (response, data) = try requestHandler(request)
            } else {
                response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: Self.statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                data = Self.responseData
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
