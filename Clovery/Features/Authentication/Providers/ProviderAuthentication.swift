import Foundation

enum ProviderAuthorizationResult: Equatable {
    case authorized(code: String)
    case cancelled
    case unavailable
    case failed
}

@MainActor
protocol ProviderAuthorizationProviding: AnyObject {
    var isAvailable: Bool { get }
    func authorize(nonce: String) async -> ProviderAuthorizationResult
}

enum FederatedLoginOutcome: Equatable {
    case authenticated
    case cancelled
    case unavailable
    case requiresExistingAccountBinding
    case failed
}

@MainActor
final class FederatedLoginCoordinator {
    private let api: FederatedAuthenticationAPIProtocol
    private let deviceRegistration: () throws -> DeviceRegistration
    private let acceptSession: (AuthSessionResponse) throws -> Void

    init(
        api: FederatedAuthenticationAPIProtocol,
        deviceRegistration: @escaping () throws -> DeviceRegistration,
        acceptSession: @escaping (AuthSessionResponse) throws -> Void
    ) {
        self.api = api
        self.deviceRegistration = deviceRegistration
        self.acceptSession = acceptSession
    }

    func authenticate(
        provider: IdentityProvider,
        using authorizer: ProviderAuthorizationProviding
    ) async -> FederatedLoginOutcome {
        guard authorizer.isAvailable else {
            return .unavailable
        }

        do {
            let intent = try await api.startFederatedLogin(provider: provider)
            switch await authorizer.authorize(nonce: intent.nonce) {
            case let .authorized(code):
                let session = try await api.completeFederatedLogin(
                    provider: provider,
                    intentID: intent.intentID,
                    nonce: intent.nonce,
                    authorizationCode: code,
                    device: try deviceRegistration()
                )
                try acceptSession(session)
                return .authenticated
            case .cancelled:
                return .cancelled
            case .unavailable:
                return .unavailable
            case .failed:
                return .failed
            }
        } catch let error as APIError {
            if error.code == "identity_not_bound" {
                return .requiresExistingAccountBinding
            }
            if error.code == "identity_provider_unavailable" ||
                error.code == "identity_provider_unsupported"
            {
                return .unavailable
            }
            return .failed
        } catch {
            return .failed
        }
    }
}

enum PasskeyAuthorizationResult: Equatable {
    case authorized(response: [String: JSONValue])
    case cancelled
    case unavailable
    case failed
}

@MainActor
protocol PasskeyAuthorizationProviding: AnyObject {
    var isAvailable: Bool { get }
    func authorize(options: [String: JSONValue]) async -> PasskeyAuthorizationResult
}

enum PasskeyLoginOutcome: Equatable {
    case authenticated
    case cancelled
    case unavailable
    case failed
}

@MainActor
final class PasskeyLoginCoordinator {
    private let api: PasskeyAuthenticationAPIProtocol
    private let deviceRegistration: () throws -> DeviceRegistration
    private let acceptSession: (AuthSessionResponse) throws -> Void

    init(
        api: PasskeyAuthenticationAPIProtocol,
        deviceRegistration: @escaping () throws -> DeviceRegistration,
        acceptSession: @escaping (AuthSessionResponse) throws -> Void
    ) {
        self.api = api
        self.deviceRegistration = deviceRegistration
        self.acceptSession = acceptSession
    }

    func authenticate(using authorizer: PasskeyAuthorizationProviding) async -> PasskeyLoginOutcome {
        guard authorizer.isAvailable else {
            return .unavailable
        }

        do {
            let ceremony = try await api.startPasskeyLogin()
            switch await authorizer.authorize(options: ceremony.options) {
            case let .authorized(response):
                let session = try await api.completePasskeyLogin(
                    challengeID: ceremony.challengeID,
                    response: response,
                    device: try deviceRegistration()
                )
                try acceptSession(session)
                return .authenticated
            case .cancelled:
                return .cancelled
            case .unavailable:
                return .unavailable
            case .failed:
                return .failed
            }
        } catch {
            return .failed
        }
    }
}
