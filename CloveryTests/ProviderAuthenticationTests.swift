import Foundation
import XCTest
@testable import Clovery

@MainActor
final class ProviderAuthenticationTests: XCTestCase {
    func testBase64URLRemovesPaddingAndUnsafeCharacters() {
        XCTAssertEqual(Data([251, 255]).base64URLEncodedString(), "-_8")
    }

    func testPasskeyAssertionResponseMatchesWebAuthnShape() {
        let response = PasskeyWebAuthnSerializer.assertionResponse(
            credentialID: Data([1]),
            authenticatorData: Data([2]),
            clientDataJSON: Data([3]),
            signature: Data([4]),
            userID: Data([5])
        )

        XCTAssertEqual(response["id"], .string("AQ"))
        XCTAssertEqual(response["rawId"], .string("AQ"))
        XCTAssertEqual(response["type"], .string("public-key"))
        XCTAssertEqual(
            response["response"],
            .object([
                "authenticatorData": .string("Ag"),
                "clientDataJSON": .string("Aw"),
                "signature": .string("BA"),
                "userHandle": .string("BQ")
            ])
        )
    }

    func testProviderCancellationIsNotFailure() {
        XCTAssertEqual(ProviderAuthorizationResult.cancelled, .cancelled)
    }

    func testFederatedLoginPreservesServerIntentAndNonce() async {
        let api = FederatedAuthenticationAPISpy()
        let authorizer = ProviderAuthorizationSpy(result: .authorized(code: "provider-code"))
        var acceptedSession: AuthSessionResponse?
        let coordinator = FederatedLoginCoordinator(
            api: api,
            deviceRegistration: { Self.device },
            acceptSession: { acceptedSession = $0 }
        )

        let outcome = await coordinator.authenticate(provider: .apple, using: authorizer)

        XCTAssertEqual(outcome, .authenticated)
        XCTAssertEqual(api.completedIntentID, "server-intent")
        XCTAssertEqual(api.completedNonce, "server-nonce")
        XCTAssertEqual(api.completedAuthorizationCode, "provider-code")
        XCTAssertEqual(acceptedSession?.accountID, "account")
    }

    func testIdentityNotBoundRequiresExistingAccountBinding() async {
        let api = FederatedAuthenticationAPISpy()
        api.completeError = APIError.server(
            code: "identity_not_bound",
            message: "This login method is not bound.",
            statusCode: 409
        )
        let coordinator = FederatedLoginCoordinator(
            api: api,
            deviceRegistration: { Self.device },
            acceptSession: { _ in XCTFail("unbound identity must not create a session") }
        )

        let outcome = await coordinator.authenticate(
            provider: .google,
            using: ProviderAuthorizationSpy(result: .authorized(code: "provider-code"))
        )

        XCTAssertEqual(outcome, .requiresExistingAccountBinding)
    }

    func testProviderCancellationSkipsBackendCompletion() async {
        let api = FederatedAuthenticationAPISpy()
        let coordinator = FederatedLoginCoordinator(
            api: api,
            deviceRegistration: { Self.device },
            acceptSession: { _ in XCTFail("cancelled login must not create a session") }
        )

        let outcome = await coordinator.authenticate(
            provider: .apple,
            using: ProviderAuthorizationSpy(result: .cancelled)
        )

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(api.completeCallCount, 0)
    }

    private static let device = DeviceRegistration(
        deviceID: "device",
        platform: "ios",
        displayName: "Test iPhone"
    )
}

@MainActor
private final class ProviderAuthorizationSpy: ProviderAuthorizationProviding {
    let isAvailable = true
    private let result: ProviderAuthorizationResult

    init(result: ProviderAuthorizationResult) {
        self.result = result
    }

    func authorize(nonce: String) async -> ProviderAuthorizationResult {
        result
    }
}

@MainActor
private final class FederatedAuthenticationAPISpy: FederatedAuthenticationAPIProtocol {
    var completeError: Error?
    private(set) var completeCallCount = 0
    private(set) var completedIntentID: String?
    private(set) var completedNonce: String?
    private(set) var completedAuthorizationCode: String?

    func startFederatedLogin(
        provider: IdentityProvider
    ) async throws -> FederationIntentResponse {
        FederationIntentResponse(
            intentID: "server-intent",
            provider: provider.rawValue,
            nonce: "server-nonce",
            expiresIn: 300
        )
    }

    func completeFederatedLogin(
        provider: IdentityProvider,
        intentID: String,
        nonce: String,
        authorizationCode: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        completeCallCount += 1
        completedIntentID = intentID
        completedNonce = nonce
        completedAuthorizationCode = authorizationCode
        if let completeError {
            throw completeError
        }
        return AuthSessionResponse(
            accountID: "account",
            vaultID: "vault",
            accessToken: "access",
            accessTokenExpiresIn: 900,
            refreshToken: "refresh",
            recoveryCodes: nil
        )
    }
}
