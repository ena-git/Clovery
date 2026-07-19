import AuthenticationServices
import Foundation

@MainActor
final class PasskeyAuthenticationProvider: PasskeyAuthorizationProviding {
    let isAvailable = true

    private let presentationAnchor: @MainActor () -> ASPresentationAnchor
    private var bridge: AuthorizationControllerBridge?

    init(
        presentationAnchor: @escaping @MainActor () -> ASPresentationAnchor = AuthenticationPresentationAnchor.current
    ) {
        self.presentationAnchor = presentationAnchor
    }

    func authorize(options: [String: JSONValue]) async -> PasskeyAuthorizationResult {
        guard bridge == nil, let request = makeRequest(options: options) else {
            return .unavailable
        }

        let bridge = AuthorizationControllerBridge(presentationAnchor: presentationAnchor)
        self.bridge = bridge
        defer { self.bridge = nil }

        switch await bridge.perform(requests: [request]) {
        case let .success(authorization):
            guard
                let assertion = authorization.credential
                    as? ASAuthorizationPlatformPublicKeyCredentialAssertion
            else {
                return .failed
            }
            return .authorized(
                response: PasskeyWebAuthnSerializer.assertionResponse(
                    credentialID: assertion.credentialID,
                    authenticatorData: assertion.rawAuthenticatorData,
                    clientDataJSON: assertion.rawClientDataJSON,
                    signature: assertion.signature,
                    userID: assertion.userID
                )
            )
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code == .canceled {
                return .cancelled
            }
            return .failed
        }
    }

    private func makeRequest(
        options: [String: JSONValue]
    ) -> ASAuthorizationPlatformPublicKeyCredentialAssertionRequest? {
        guard
            let publicKey = options.object(named: "publicKey"),
            let relyingPartyIdentifier = publicKey.string(named: "rpId"),
            let challengeValue = publicKey.string(named: "challenge"),
            let challenge = Data(base64URLEncoded: challengeValue)
        else {
            return nil
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: relyingPartyIdentifier
        )
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.allowedCredentials = publicKey
            .array(named: "allowCredentials")?
            .compactMap(Self.credentialDescriptor) ?? []

        switch publicKey.string(named: "userVerification") {
        case "required":
            request.userVerificationPreference = .required
        case "discouraged":
            request.userVerificationPreference = .discouraged
        default:
            request.userVerificationPreference = .preferred
        }
        return request
    }

    private static func credentialDescriptor(
        value: JSONValue
    ) -> ASAuthorizationPlatformPublicKeyCredentialDescriptor? {
        guard
            case let .object(object) = value,
            case let .string(identifier)? = object["id"],
            let credentialID = Data(base64URLEncoded: identifier)
        else {
            return nil
        }
        return ASAuthorizationPlatformPublicKeyCredentialDescriptor(
            credentialID: credentialID
        )
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func object(named name: String) -> [String: JSONValue]? {
        guard case let .object(value)? = self[name] else {
            return nil
        }
        return value
    }

    func array(named name: String) -> [JSONValue]? {
        guard case let .array(value)? = self[name] else {
            return nil
        }
        return value
    }

    func string(named name: String) -> String? {
        guard case let .string(value)? = self[name] else {
            return nil
        }
        return value
    }
}
