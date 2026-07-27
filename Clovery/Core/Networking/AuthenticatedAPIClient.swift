import Foundation

@MainActor
protocol AuthenticatedSessionControlling: AnyObject {
    func authenticationSession() -> AuthenticationSession?
    func refreshAuthenticatedSession() async throws -> AuthenticationSession
    func logout()
}

enum AuthenticatedAPIClientError: Error, Equatable {
    case authenticationRequired
}

actor AuthenticatedAPIClient {
    private let client: APIClient
    private let sessionController: AuthenticatedSessionControlling
    private let now: () -> Date
    private var refreshTask: Task<AuthenticationSession, Error>?

    init(
        client: APIClient,
        sessionController: AuthenticatedSessionControlling,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.sessionController = sessionController
        self.now = now
    }

    func send<Response: Decodable>(
        _ request: APIRequest,
        decoding responseType: Response.Type
    ) async throws -> Response {
        let resolved = try await validSession()
        do {
            return try await client.send(
                request.authenticated(with: resolved.session.accessToken),
                decoding: responseType
            )
        } catch let error as APIError where shouldRetry(
            error: error, request: request, alreadyRefreshed: resolved.refreshed
        ) {
            let refreshed = try await refreshSession()
            return try await client.send(
                request.authenticated(with: refreshed.accessToken),
                decoding: responseType
            )
        }
    }

    func sendWithoutResponse(_ request: APIRequest) async throws {
        let resolved = try await validSession()
        do {
            try await client.sendWithoutResponse(
                request.authenticated(with: resolved.session.accessToken)
            )
        } catch let error as APIError where shouldRetry(
            error: error, request: request, alreadyRefreshed: resolved.refreshed
        ) {
            let refreshed = try await refreshSession()
            try await client.sendWithoutResponse(
                request.authenticated(with: refreshed.accessToken)
            )
        }
    }

    private func validSession() async throws -> ResolvedSession {
        guard let session = await sessionController.authenticationSession() else {
            throw AuthenticatedAPIClientError.authenticationRequired
        }
        if session.accessTokenExpiresAt.timeIntervalSince(now()) > 60 {
            return ResolvedSession(session: session, refreshed: false)
        }
        return ResolvedSession(session: try await refreshSession(), refreshed: true)
    }

    private func refreshSession() async throws -> AuthenticationSession {
        if let refreshTask {
            return try await refreshTask.value
        }
        let controller = sessionController
        let task = Task { @MainActor in
            try await controller.refreshAuthenticatedSession()
        }
        refreshTask = task
        do {
            let session = try await task.value
            refreshTask = nil
            return session
        } catch {
            refreshTask = nil
            if isTerminalRefreshRejection(error) {
                await controller.logout()
            }
            throw error
        }
    }

    private func shouldRetry(
        error: APIError,
        request: APIRequest,
        alreadyRefreshed: Bool
    ) -> Bool {
        error.statusCode == 401 && request.allowsAuthenticationRetry && !alreadyRefreshed
    }

    private func isTerminalRefreshRejection(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else {
            return false
        }
        return apiError.statusCode == 401 || apiError.code == "invalid_refresh_token"
    }
}

private struct ResolvedSession {
    let session: AuthenticationSession
    let refreshed: Bool
}
