import XCTest
@testable import Clovery

@MainActor
final class SignUpViewModelTests: XCTestCase {
    func testMismatchedConfirmationBlocksRegistration() async {
        let api = AuthenticationAPISpy()
        let controller = makeController(api: api)
        let viewModel = SignUpViewModel(api: api, sessionController: controller)
        viewModel.loginID = "clovery_user"
        viewModel.password = "eight888"
        viewModel.confirmPassword = "different"

        await viewModel.submit()

        XCTAssertEqual(viewModel.validationError, .passwordsDoNotMatch)
        XCTAssertEqual(api.registerCallCount, 0)
    }

    func testSuccessfulRegistrationRequiresRecoveryCodesAcknowledgement() async {
        let api = AuthenticationAPISpy()
        api.registerResponse = AuthSessionResponse(
            accountID: "account",
            vaultID: "vault",
            accessToken: "access",
            accessTokenExpiresIn: 900,
            refreshToken: "refresh",
            recoveryCodes: ["one", "two", "three", "four", "five", "six", "seven", "eight"]
        )
        let controller = makeController(api: api)
        let viewModel = SignUpViewModel(api: api, sessionController: controller)
        viewModel.loginID = "Clovery_User"
        viewModel.password = "eight888"
        viewModel.confirmPassword = "eight888"

        await viewModel.submit()

        XCTAssertEqual(viewModel.recoveryCodes?.count, 8)
        XCTAssertEqual(viewModel.loginID, "clovery_user")
        XCTAssertEqual(controller.state.requiresRecoveryCodeAcknowledgement, true)
    }

    private func makeController(api: AuthenticationAPIProtocol) -> ApplicationSessionController {
        ApplicationSessionController(
            api: api,
            sessionStore: AuthenticationSessionStore(
                keychain: KeychainStore(service: "com.clovery.tests.\(UUID().uuidString)")
            ),
            deviceIdentityStore: DeviceIdentityStore(
                keychain: KeychainStore(service: "com.clovery.tests.\(UUID().uuidString)")
            )
        )
    }
}

@MainActor
private final class AuthenticationAPISpy: AuthenticationAPIProtocol {
    var registerResponse = AuthSessionResponse(
        accountID: "account",
        vaultID: "vault",
        accessToken: "access",
        accessTokenExpiresIn: 900,
        refreshToken: "refresh",
        recoveryCodes: nil
    )
    var registerError: Error?
    var loginError: Error?
    var loginDelayNanoseconds: UInt64 = 0
    private(set) var registerCallCount = 0
    private(set) var loginCallCount = 0

    func register(
        loginID: String,
        password: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        return registerResponse
    }

    func login(
        loginID: String,
        password: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        loginCallCount += 1
        if loginDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: loginDelayNanoseconds)
        }
        if let loginError {
            throw loginError
        }
        return registerResponse
    }

    func refresh(refreshToken: String) async throws -> AuthSessionResponse {
        registerResponse
    }

    func startFederatedLogin(provider: IdentityProvider) async throws -> FederationIntentResponse {
        FederationIntentResponse(intentID: "intent", provider: provider.rawValue, nonce: "nonce", expiresIn: 300)
    }

    func completeFederatedLogin(
        provider: IdentityProvider,
        intentID: String,
        nonce: String,
        authorizationCode: String,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        registerResponse
    }

    func startPasskeyLogin() async throws -> PasskeyCeremonyResponse {
        PasskeyCeremonyResponse(challengeID: "challenge", options: [:], expiresIn: 300)
    }

    func completePasskeyLogin(
        challengeID: String,
        response: [String: JSONValue],
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        registerResponse
    }
}
