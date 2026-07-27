import Foundation
import XCTest
@testable import Clovery

@MainActor
func makeVaultAuthenticatedClient() -> AuthenticatedAPIClient {
    let baseClient = APIClient(
        configuration: APIConfiguration(baseURL: URL(string: "https://api.example")!),
        session: makeVaultURLSession()
    )
    return AuthenticatedAPIClient(
        client: baseClient,
        sessionController: VaultSessionControllerSpy()
    )
}

func makeVaultURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [VaultAPIURLProtocolStub.self]
    return URLSession(configuration: configuration)
}

@MainActor
private final class VaultSessionControllerSpy: AuthenticatedSessionControlling {
    func authenticationSession() -> AuthenticationSession? {
        AuthenticationSession(
            accountID: "account",
            vaultID: "vault",
            accessToken: "vault-access",
            accessTokenExpiresAt: Date().addingTimeInterval(900)
        )
    }

    func refreshAuthenticatedSession() async throws -> AuthenticationSession {
        try XCTUnwrap(authenticationSession())
    }

    func logout() {}
}

final class VaultAPIURLProtocolStub: URLProtocol {
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
            HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
            Data()
        )
        client?.urlProtocol(self, didReceive: response.0, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
