import Combine
import Foundation

@MainActor
protocol IdentityClaimRegistrationSessionHandling: AnyObject {
    func deviceRegistration() throws -> DeviceRegistration
    func accept(_ response: AuthSessionResponse) throws
}

@MainActor
final class IdentityClaimRegistrationViewModel: ObservableObject {
    @Published var loginID = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var hasAcceptedLegalTerms = false
    @Published private(set) var validationError: AuthenticationValidationIssue?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSubmitting = false
    @Published private(set) var reauthorizationRequest: IdentityProvider?

    private let api: IdentityClaimAPIProtocol
    private let sessionHandler: IdentityClaimRegistrationSessionHandling
    private let sourceKind: BootstrapSourceKind
    private let registrationRequestID: UUID
    private let now: () -> Date
    private var claim: IdentityClaimContext?

    init(
        api: IdentityClaimAPIProtocol,
        sessionHandler: IdentityClaimRegistrationSessionHandling,
        claim: IdentityClaimContext,
        sourceKind: BootstrapSourceKind,
        registrationRequestID: UUID = UUID(),
        now: @escaping () -> Date = Date.init
    ) {
        self.api = api
        self.sessionHandler = sessionHandler
        self.claim = claim
        self.sourceKind = sourceKind
        self.registrationRequestID = registrationRequestID
        self.now = now
    }

    var hasActiveClaim: Bool {
        claim != nil
    }

    func submit() async {
        guard !isSubmitting else {
            return
        }
        validationError = nil
        errorMessage = nil

        guard let claim else {
            errorMessage = "登录验证已过期，请重新授权"
            return
        }
        guard claim.expiresAt > now() else {
            requestReauthorization(for: claim.provider)
            return
        }

        let normalizedID = AuthenticationValidation.normalizedCloveryID(loginID)
        guard AuthenticationValidation.isValidCloveryID(normalizedID) else {
            validationError = .invalidCloveryID
            return
        }
        guard AuthenticationValidation.isValidPassword(password) else {
            validationError = .invalidPassword
            return
        }
        guard password == confirmPassword else {
            validationError = .passwordsDoNotMatch
            return
        }
        guard hasAcceptedLegalTerms else {
            validationError = .legalTermsNotAccepted
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let response = try await api.register(
                loginID: normalizedID,
                password: password,
                claim: claim,
                registrationRequestID: registrationRequestID,
                sourceKind: sourceKind,
                device: try sessionHandler.deviceRegistration()
            )
            try sessionHandler.accept(response)
            loginID = normalizedID
            clearClaimAndPasswords()
        } catch {
            handle(error, provider: claim.provider)
        }
    }

    func consumeReauthorizationRequest() -> IdentityProvider? {
        defer { reauthorizationRequest = nil }
        return reauthorizationRequest
    }

    func clearSensitiveState() {
        clearClaimAndPasswords()
        reauthorizationRequest = nil
    }

    private func handle(_ error: Error, provider: IdentityProvider) {
        guard let apiError = error as? APIError else {
            errorMessage = "网络暂时不可用，请稍后再试"
            return
        }
        switch apiError.code {
        case "login_id_unavailable":
            errorMessage = "这个 Clovery ID 已被使用"
        case "identity_claim_expired", "identity_claim_invalid":
            requestReauthorization(for: provider)
        case "rate_limited":
            errorMessage = "尝试次数过多，请稍后再试"
        default:
            errorMessage = "创建账户失败，请稍后再试"
        }
    }

    private func requestReauthorization(for provider: IdentityProvider) {
        claim = nil
        password = ""
        confirmPassword = ""
        errorMessage = "登录验证已过期，请重新授权"
        reauthorizationRequest = provider
    }

    private func clearClaimAndPasswords() {
        claim = nil
        password = ""
        confirmPassword = ""
    }
}

extension ApplicationSessionController: IdentityClaimRegistrationSessionHandling {}
