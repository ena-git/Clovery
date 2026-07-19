import Combine
import Foundation

@MainActor
final class ApplicationSessionController: ObservableObject {
    @Published private(set) var state: AuthenticationState = .unauthenticated

    private let api: AuthenticationAPIProtocol
    private let sessionStore: AuthenticationSessionStore
    private let deviceIdentityStore: DeviceIdentityStore

    init(
        api: AuthenticationAPIProtocol,
        sessionStore: AuthenticationSessionStore = AuthenticationSessionStore(),
        deviceIdentityStore: DeviceIdentityStore = DeviceIdentityStore()
    ) {
        self.api = api
        self.sessionStore = sessionStore
        self.deviceIdentityStore = deviceIdentityStore
    }

    func deviceRegistration() throws -> DeviceRegistration {
        try deviceIdentityStore.deviceRegistration()
    }

    func accept(_ response: AuthSessionResponse) throws {
        try sessionStore.save(session: response)
        let session = AuthenticationSession(
            accountID: response.accountID,
            vaultID: response.vaultID,
            accessToken: response.accessToken,
            accessTokenExpiresAt: Date().addingTimeInterval(TimeInterval(response.accessTokenExpiresIn))
        )
        if let recoveryCodes = response.recoveryCodes, !recoveryCodes.isEmpty {
            state = .recoveryCodes(session, recoveryCodes)
        } else {
            state = .authenticated(session)
        }
    }

    func acknowledgeRecoveryCodes() {
        guard case let .recoveryCodes(session, _) = state else {
            return
        }
        state = .authenticated(session)
    }

    func restoreSession() async {
        guard let refreshToken = try? sessionStore.refreshToken() else {
            state = .unauthenticated
            return
        }

        do {
            let response = try await api.refresh(refreshToken: refreshToken)
            try accept(response)
        } catch {
            sessionStore.clear()
            state = .unauthenticated
        }
    }

    func logout() {
        sessionStore.clear()
        state = .unauthenticated
    }
}
