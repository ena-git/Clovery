import Foundation
import XCTest
@testable import Clovery

@MainActor
final class AuthenticatedAPIClientTests: XCTestCase {
    override func tearDown() {
        AuthenticatedURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testAttachesCurrentBearerToken() async throws {
        let controller = SessionControllerSpy(session: makeSession(token: "current-access"))
        let client = makeClient(controller: controller) { request, _ in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer current-access")
            return Self.response(request: request, status: 200, body: #"{"value":"ok"}"#)
        }

        let value = try await client.send(
            APIRequest(method: "GET", path: "/v1/vault"), decoding: TestPayload.self
        )

        XCTAssertEqual(value.value, "ok")
        XCTAssertEqual(controller.refreshCalls, 0)
    }

    func testRefreshesNearExpiryAndUsesRotatedSession() async throws {
        let controller = SessionControllerSpy(
            session: makeSession(token: "expiring", expiresIn: 30),
            refreshedSession: makeSession(token: "rotated-access")
        )
        let client = makeClient(controller: controller) { request, _ in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer rotated-access")
            return Self.response(request: request, status: 200, body: #"{"value":"ok"}"#)
        }

        _ = try await client.send(
            APIRequest(method: "GET", path: "/v1/vault"), decoding: TestPayload.self
        )

        XCTAssertEqual(controller.refreshCalls, 1)
        XCTAssertTrue(controller.savedRotatedSession)
    }

    func testConcurrentNearExpiryRequestsCoalesceRefresh() async throws {
        let controller = SessionControllerSpy(
            session: makeSession(token: "expiring", expiresIn: 30),
            refreshedSession: makeSession(token: "rotated-access"),
            refreshDelayNanoseconds: 100_000_000
        )
        let client = makeClient(controller: controller) { request, _ in
            Self.response(request: request, status: 200, body: #"{"value":"ok"}"#)
        }

        async let first = client.send(
            APIRequest(method: "GET", path: "/v1/vault"), decoding: TestPayload.self
        )
        async let second = client.send(
            APIRequest(method: "GET", path: "/v1/account"), decoding: TestPayload.self
        )
        _ = try await (first, second)

        XCTAssertEqual(controller.refreshCalls, 1)
    }

    func testRetriesSafeRequestOnceAfterUnauthorized() async throws {
        let controller = SessionControllerSpy(
            session: makeSession(token: "rejected-access"),
            refreshedSession: makeSession(token: "rotated-access")
        )
        let client = makeClient(controller: controller) { request, count in
            if count == 1 {
                return Self.response(
                    request: request, status: 401,
                    body: #"{"code":"unauthorized","message":"Authentication failed."}"#
                )
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer rotated-access")
            return Self.response(request: request, status: 200, body: #"{"value":"ok"}"#)
        }

        let value = try await client.send(
            APIRequest(method: "GET", path: "/v1/vault"), decoding: TestPayload.self
        )

        XCTAssertEqual(value.value, "ok")
        XCTAssertEqual(controller.refreshCalls, 1)
        XCTAssertEqual(AuthenticatedURLProtocolStub.requestCount, 2)
    }

    func testDoesNotRetryUnsafePostWithoutStableRequestID() async throws {
        let controller = SessionControllerSpy(
            session: makeSession(token: "rejected-access"),
            refreshedSession: makeSession(token: "rotated-access")
        )
        let client = makeClient(controller: controller) { request, _ in
            Self.response(
                request: request, status: 401,
                body: #"{"code":"unauthorized","message":"Authentication failed."}"#
            )
        }

        do {
            _ = try await client.send(
                APIRequest(method: "POST", path: "/v1/vault/migrations/id/verify"),
                decoding: TestPayload.self
            )
            XCTFail("unsafe POST should not be retried")
        } catch let error as APIError {
            XCTAssertEqual(error.statusCode, 401)
        }
        XCTAssertEqual(controller.refreshCalls, 0)
        XCTAssertEqual(AuthenticatedURLProtocolStub.requestCount, 1)
    }

    func testRefreshFailureLogsOutOnlyForTerminalRejection() async throws {
        for test in [
            (APIError.server(code: "invalid_refresh_token", message: "Authentication failed.", statusCode: 401), 1),
            (APIError.transport("offline"), 0),
        ] {
            let controller = SessionControllerSpy(
                session: makeSession(token: "expiring", expiresIn: 30),
                refreshedSession: makeSession(token: "unused"),
                refreshError: test.0
            )
            let client = makeClient(controller: controller) { request, _ in
                Self.response(request: request, status: 200, body: #"{"value":"ok"}"#)
            }

            do {
                _ = try await client.send(
                    APIRequest(method: "GET", path: "/v1/vault"), decoding: TestPayload.self
                )
                XCTFail("refresh should fail")
            } catch {
                XCTAssertEqual(controller.logoutCalls, test.1)
            }
        }
    }

    private func makeClient(
        controller: SessionControllerSpy,
        handler: @escaping (URLRequest, Int) throws -> (HTTPURLResponse, Data)
    ) -> AuthenticatedAPIClient {
        AuthenticatedURLProtocolStub.reset(handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthenticatedURLProtocolStub.self]
        let baseClient = APIClient(
            configuration: APIConfiguration(baseURL: URL(string: "https://api.test.invalid")!),
            session: URLSession(configuration: configuration)
        )
        return AuthenticatedAPIClient(client: baseClient, sessionController: controller)
    }

    private func makeSession(token: String, expiresIn: TimeInterval = 900) -> AuthenticationSession {
        AuthenticationSession(
            accountID: "account",
            vaultID: "vault",
            accessToken: token,
            accessTokenExpiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    nonisolated private static func response(
        request: URLRequest,
        status: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
    }
}

private struct TestPayload: Codable, Equatable {
    let value: String
}

@MainActor
private final class SessionControllerSpy: AuthenticatedSessionControlling {
    private var session: AuthenticationSession?
    private let refreshedSession: AuthenticationSession
    private let refreshDelayNanoseconds: UInt64
    private let refreshError: Error?
    private(set) var refreshCalls = 0
    private(set) var logoutCalls = 0
    private(set) var savedRotatedSession = false

    init(
        session: AuthenticationSession,
        refreshedSession: AuthenticationSession? = nil,
        refreshDelayNanoseconds: UInt64 = 0,
        refreshError: Error? = nil
    ) {
        self.session = session
        self.refreshedSession = refreshedSession ?? session
        self.refreshDelayNanoseconds = refreshDelayNanoseconds
        self.refreshError = refreshError
    }

    func authenticationSession() -> AuthenticationSession? {
        session
    }

    func refreshAuthenticatedSession() async throws -> AuthenticationSession {
        refreshCalls += 1
        if refreshDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: refreshDelayNanoseconds)
        }
        if let refreshError {
            throw refreshError
        }
        session = refreshedSession
        savedRotatedSession = true
        return refreshedSession
    }

    func logout() {
        logoutCalls += 1
        session = nil
    }
}

private final class AuthenticatedURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest, Int) throws -> (HTTPURLResponse, Data))?
    static var requestCount = 0
    private static let lock = NSLock()

    static func reset(handler: @escaping (URLRequest, Int) throws -> (HTTPURLResponse, Data)) {
        lock.lock()
        self.handler = handler
        requestCount = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            Self.lock.lock()
            Self.requestCount += 1
            let count = Self.requestCount
            let handler = Self.handler
            Self.lock.unlock()
            guard let handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request, count)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
