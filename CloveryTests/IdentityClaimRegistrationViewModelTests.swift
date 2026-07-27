import XCTest
@testable import Clovery

@MainActor
final class IdentityClaimRegistrationViewModelTests: XCTestCase {
    func testCloveryIDUsesFourToTwentyFourCharacterValidation() async {
        let fixture = makeFixture()
        fixture.viewModel.loginID = "abc"
        fixture.viewModel.password = "eight888"
        fixture.viewModel.confirmPassword = "eight888"

        await fixture.viewModel.submit()

        XCTAssertEqual(fixture.viewModel.validationError, .invalidCloveryID)
        XCTAssertEqual(fixture.api.calls.count, 0)

        fixture.viewModel.loginID = "abcd"
        await fixture.viewModel.submit()

        XCTAssertEqual(fixture.api.calls.count, 1)
        XCTAssertEqual(fixture.api.calls.first?.loginID, "abcd")

        let tooLongFixture = makeFixture()
        tooLongFixture.viewModel.loginID = "a234567890123456789012345"
        tooLongFixture.viewModel.password = "eight888"
        tooLongFixture.viewModel.confirmPassword = "eight888"

        await tooLongFixture.viewModel.submit()

        XCTAssertEqual(tooLongFixture.viewModel.validationError, .invalidCloveryID)
        XCTAssertEqual(tooLongFixture.api.calls.count, 0)
    }

    func testPasswordAcceptsEightAndRejectsSevenCharacters() async {
        let fixture = makeFixture()
        fixture.viewModel.loginID = "clovery_user"
        fixture.viewModel.password = "seven77"
        fixture.viewModel.confirmPassword = "seven77"

        await fixture.viewModel.submit()

        XCTAssertEqual(fixture.viewModel.validationError, .invalidPassword)
        XCTAssertEqual(fixture.api.calls.count, 0)

        fixture.viewModel.password = "eight888"
        fixture.viewModel.confirmPassword = "eight888"
        await fixture.viewModel.submit()

        XCTAssertEqual(fixture.api.calls.count, 1)
    }

    func testPasswordConfirmationMustMatch() async {
        let fixture = makeFixture()
        fixture.viewModel.loginID = "clovery_user"
        fixture.viewModel.password = "eight888"
        fixture.viewModel.confirmPassword = "different8"

        await fixture.viewModel.submit()

        XCTAssertEqual(fixture.viewModel.validationError, .passwordsDoNotMatch)
        XCTAssertEqual(fixture.api.calls.count, 0)
    }

    func testRegistrationRequestIDRemainsStableAcrossRetry() async {
        let fixture = makeFixture()
        fixture.api.results = [
            .failure(APIError.transport("offline")),
            .success(Self.sessionResponse)
        ]
        fillValidForm(fixture.viewModel)

        await fixture.viewModel.submit()
        await fixture.viewModel.submit()

        XCTAssertEqual(fixture.api.calls.count, 2)
        XCTAssertEqual(
            fixture.api.calls.first?.registrationRequestID,
            fixture.api.calls.last?.registrationRequestID
        )
    }

    func testExpiredClaimBlocksSubmitAndRequestsProviderAuthorizationAgain() async {
        let fixture = makeFixture(
            claim: IdentityClaimContext(
                provider: .apple,
                token: "expired-secret",
                expiresAt: Date(timeIntervalSince1970: 99)
            ),
            now: { Date(timeIntervalSince1970: 100) }
        )
        fillValidForm(fixture.viewModel)

        await fixture.viewModel.submit()

        XCTAssertEqual(fixture.api.calls.count, 0)
        XCTAssertEqual(fixture.viewModel.reauthorizationRequest, .apple)
        XCTAssertEqual(fixture.viewModel.errorMessage, "登录验证已过期，请重新授权")
        XCTAssertFalse(fixture.viewModel.hasActiveClaim)
    }

    func testUnavailableLoginIDPreservesClaimAndUserInput() async {
        let fixture = makeFixture()
        fixture.api.results = [
            .failure(
                APIError.server(
                    code: "login_id_unavailable",
                    message: "Already used.",
                    statusCode: 409
                )
            )
        ]
        fillValidForm(fixture.viewModel)

        await fixture.viewModel.submit()

        XCTAssertEqual(fixture.viewModel.loginID, "clovery_user")
        XCTAssertEqual(fixture.viewModel.password, "eight888")
        XCTAssertEqual(fixture.viewModel.confirmPassword, "eight888")
        XCTAssertTrue(fixture.viewModel.hasActiveClaim)
        XCTAssertEqual(fixture.viewModel.errorMessage, "这个 Clovery ID 已被使用")
    }

    func testSuccessAcceptsExactReturnedAccountAndVaultSession() async {
        let fixture = makeFixture()
        fillValidForm(fixture.viewModel)

        await fixture.viewModel.submit()

        XCTAssertEqual(fixture.sessionHandler.acceptedResponse, Self.sessionResponse)
        XCTAssertFalse(fixture.viewModel.hasActiveClaim)
    }

    func testFlowExitClearsClaimTokenAndPasswordsFromMemory() {
        let fixture = makeFixture()
        fillValidForm(fixture.viewModel)

        fixture.viewModel.clearSensitiveState()

        XCTAssertFalse(fixture.viewModel.hasActiveClaim)
        XCTAssertEqual(fixture.viewModel.password, "")
        XCTAssertEqual(fixture.viewModel.confirmPassword, "")
    }

    private func makeFixture(
        claim: IdentityClaimContext = IdentityClaimContext(
            provider: .apple,
            token: "claim-secret",
            expiresAt: Date(timeIntervalSince1970: 200)
        ),
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 100) }
    ) -> Fixture {
        let api = IdentityClaimRegistrationAPISpy()
        let sessionHandler = IdentityClaimRegistrationSessionSpy()
        let viewModel = IdentityClaimRegistrationViewModel(
            api: api,
            sessionHandler: sessionHandler,
            claim: claim,
            sourceKind: .legacyLocal,
            registrationRequestID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            now: now
        )
        return Fixture(api: api, sessionHandler: sessionHandler, viewModel: viewModel)
    }

    private func fillValidForm(_ viewModel: IdentityClaimRegistrationViewModel) {
        viewModel.loginID = "clovery_user"
        viewModel.password = "eight888"
        viewModel.confirmPassword = "eight888"
    }

    private static let sessionResponse = AuthSessionResponse(
        accountID: "exact-account",
        vaultID: "exact-vault",
        accessToken: "access",
        accessTokenExpiresIn: 900,
        refreshToken: "refresh",
        recoveryCodes: nil
    )
}

private struct Fixture {
    let api: IdentityClaimRegistrationAPISpy
    let sessionHandler: IdentityClaimRegistrationSessionSpy
    let viewModel: IdentityClaimRegistrationViewModel
}

private struct IdentityClaimRegistrationCall {
    let loginID: String
    let registrationRequestID: UUID
}

private final class IdentityClaimRegistrationAPISpy: IdentityClaimAPIProtocol {
    var results: [Result<AuthSessionResponse, Error>] = [.success(
        AuthSessionResponse(
            accountID: "exact-account",
            vaultID: "exact-vault",
            accessToken: "access",
            accessTokenExpiresIn: 900,
            refreshToken: "refresh",
            recoveryCodes: nil
        )
    )]
    private(set) var calls: [IdentityClaimRegistrationCall] = []

    func register(
        loginID: String,
        password: String,
        claim: IdentityClaimContext,
        registrationRequestID: UUID,
        sourceKind: BootstrapSourceKind,
        device: DeviceRegistration
    ) async throws -> AuthSessionResponse {
        calls.append(
            IdentityClaimRegistrationCall(
                loginID: loginID,
                registrationRequestID: registrationRequestID
            )
        )
        let result = results.isEmpty ? results.last : results.removeFirst()
        return try XCTUnwrap(result).get()
    }
}

@MainActor
private final class IdentityClaimRegistrationSessionSpy: IdentityClaimRegistrationSessionHandling {
    private(set) var acceptedResponse: AuthSessionResponse?

    func deviceRegistration() throws -> DeviceRegistration {
        DeviceRegistration(deviceID: "device", platform: "ios", displayName: "Test iPhone")
    }

    func accept(_ response: AuthSessionResponse) throws {
        acceptedResponse = response
    }
}
