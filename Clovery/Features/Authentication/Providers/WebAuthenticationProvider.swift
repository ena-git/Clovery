import AuthenticationServices
import Foundation

struct WebAuthenticationConfiguration: Equatable {
    let authorizationURL: URL
    let clientID: String
    let redirectURL: URL
    let scopes: [String]

    static func current(
        provider: IdentityProvider,
        bundle: Bundle = .main
    ) -> WebAuthenticationConfiguration? {
        let prefix: String
        switch provider {
        case .google:
            prefix = "Google"
        case .huawei:
            prefix = "Huawei"
        default:
            return nil
        }

        guard
            let authorizationURL = configuredURL(
                key: "Clovery\(prefix)AuthorizationURL",
                bundle: bundle
            ),
            let clientID = configuredString(
                key: "Clovery\(prefix)ClientID",
                bundle: bundle
            ),
            let redirectURL = configuredURL(
                key: "Clovery\(prefix)RedirectURL",
                bundle: bundle
            ),
            redirectURL.scheme != nil
        else {
            return nil
        }

        let scopes = configuredString(
            key: "Clovery\(prefix)Scopes",
            bundle: bundle
        )?
        .split(whereSeparator: { $0 == " " || $0 == "," })
        .map(String.init) ?? ["openid", "email"]

        return WebAuthenticationConfiguration(
            authorizationURL: authorizationURL,
            clientID: clientID,
            redirectURL: redirectURL,
            scopes: scopes
        )
    }

    private static func configuredString(
        key: String,
        bundle: Bundle
    ) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func configuredURL(
        key: String,
        bundle: Bundle
    ) -> URL? {
        guard
            let value = configuredString(key: key, bundle: bundle),
            let url = URL(string: value),
            url.scheme != nil,
            url.host != nil
        else {
            return nil
        }
        return url
    }
}

@MainActor
final class WebAuthenticationProvider: NSObject, ProviderAuthorizationProviding {
    let isAvailable: Bool

    private let configuration: WebAuthenticationConfiguration?
    private let presentationAnchor: @MainActor () -> ASPresentationAnchor
    private var session: ASWebAuthenticationSession?

    init(
        configuration: WebAuthenticationConfiguration?,
        presentationAnchor: @escaping @MainActor () -> ASPresentationAnchor = AuthenticationPresentationAnchor.current
    ) {
        self.configuration = configuration
        self.presentationAnchor = presentationAnchor
        isAvailable = configuration != nil
    }

    func authorize(nonce: String) async -> ProviderAuthorizationResult {
        guard
            session == nil,
            let configuration,
            let authorizationURL = makeAuthorizationURL(
                configuration: configuration,
                nonce: nonce
            ),
            let callbackScheme = configuration.redirectURL.scheme
        else {
            return .unavailable
        }

        return await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.session = nil
                    continuation.resume(
                        returning: Self.result(
                            callbackURL: callbackURL,
                            error: error,
                            expectedRedirectURL: configuration.redirectURL,
                            expectedState: nonce
                        )
                    )
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.session = session

            guard session.start() else {
                self.session = nil
                continuation.resume(returning: .unavailable)
                return
            }
        }
    }

    private func makeAuthorizationURL(
        configuration: WebAuthenticationConfiguration,
        nonce: String
    ) -> URL? {
        guard var components = URLComponents(
            url: configuration.authorizationURL,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURL.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: nonce),
            URLQueryItem(name: "nonce", value: nonce)
        ])
        components.queryItems = queryItems
        return components.url
    }

    private static func result(
        callbackURL: URL?,
        error: Error?,
        expectedRedirectURL: URL,
        expectedState: String
    ) -> ProviderAuthorizationResult {
        if let error = error as? ASWebAuthenticationSessionError,
           error.code == .canceledLogin
        {
            return .cancelled
        }
        guard error == nil, let callbackURL else {
            return .failed
        }
        guard
            callbackURL.scheme == expectedRedirectURL.scheme,
            callbackURL.host == expectedRedirectURL.host,
            callbackURL.path == expectedRedirectURL.path,
            let components = URLComponents(
                url: callbackURL,
                resolvingAgainstBaseURL: false
            ),
            components.value(named: "state") == expectedState,
            let code = components.value(named: "code"),
            !code.isEmpty
        else {
            return .failed
        }
        return .authorized(code: code)
    }
}

extension WebAuthenticationProvider: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        presentationAnchor()
    }
}

private extension URLComponents {
    func value(named name: String) -> String? {
        queryItems?.first(where: { $0.name == name })?.value
    }
}
