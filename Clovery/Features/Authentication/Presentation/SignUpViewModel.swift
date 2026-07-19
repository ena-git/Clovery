import Combine
import Foundation

@MainActor
final class SignUpViewModel: ObservableObject {
    @Published var loginID = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published private(set) var validationError: AuthenticationValidationIssue?
    @Published private(set) var errorMessage: String?
    @Published private(set) var recoveryCodes: [String]?
    @Published private(set) var isSubmitting = false

    private let api: AuthenticationAPIProtocol
    private let sessionController: ApplicationSessionController

    init(
        api: AuthenticationAPIProtocol,
        sessionController: ApplicationSessionController
    ) {
        self.api = api
        self.sessionController = sessionController
    }

    func submit() async {
        guard !isSubmitting else {
            return
        }
        validationError = nil
        errorMessage = nil
        recoveryCodes = nil

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

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let device = try sessionController.deviceRegistration()
            let response = try await api.register(
                loginID: normalizedID,
                password: password,
                device: device
            )
            loginID = normalizedID
            recoveryCodes = response.recoveryCodes
            try sessionController.accept(response)
        } catch {
            errorMessage = message(for: error)
        }
    }

    func acknowledgeRecoveryCodes() {
        recoveryCodes = nil
        sessionController.acknowledgeRecoveryCodes()
    }

    private func message(for error: Error) -> String {
        guard let apiError = error as? APIError else {
            return "网络暂时不可用，请稍后再试"
        }
        if apiError.code == "login_id_unavailable" {
            return "这个 Clovery ID 已被使用"
        }
        if apiError.code == "invalid_request" {
            return "请检查 Clovery ID 和密码"
        }
        if apiError.code == "rate_limited" {
            return "尝试次数过多，请稍后再试"
        }
        return "注册失败，请稍后再试"
    }
}
