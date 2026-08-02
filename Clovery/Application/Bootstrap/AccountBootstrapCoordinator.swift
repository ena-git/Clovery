import Combine
import Foundation

@MainActor
protocol BootstrapSessionControlling: AnyObject {
    func authenticationSession() -> AuthenticationSession?
    func restoreSession() async
    func logout()
}

@MainActor
protocol BootstrapNoticeControlling: AnyObject {
    var hasLegacyData: Bool { get }
    var hasAcknowledgedNotice: Bool { get }
    func acknowledgeNotice()
}

@MainActor
final class AccountBootstrapCoordinator: ObservableObject {
    @Published private(set) var route: BootstrapRoute = .loading

    private let sessionController: BootstrapSessionControlling
    private let noticeController: BootstrapNoticeControlling
    private let api: AccountBootstrapAPIProtocol
    private let checkpointStore: BootstrapCheckpointStoring
    private let pipeline: AccountBootstrapPipelining?
    private var operationTask: Task<Void, Never>?
    private var generation = UUID()

    init(
        sessionController: BootstrapSessionControlling,
        noticeController: BootstrapNoticeControlling,
        api: AccountBootstrapAPIProtocol,
        checkpointStore: BootstrapCheckpointStoring,
        pipeline: AccountBootstrapPipelining? = nil
    ) {
        self.sessionController = sessionController
        self.noticeController = noticeController
        self.api = api
        self.checkpointStore = checkpointStore
        self.pipeline = pipeline
    }

    func start() {
        cancelCurrentOperation()
        if noticeController.hasLegacyData, !noticeController.hasAcknowledgedNotice {
            route = .upgradeNotice
            return
        }
        restoreAndRoute()
    }

    func acknowledgeNotice() {
        noticeController.acknowledgeNotice()
        restoreAndRoute()
    }

    func sessionDidChange() {
        cancelCurrentOperation()
        guard let session = sessionController.authenticationSession() else {
            route = .authentication
            return
        }
        reconcile(session: session)
    }

    func retry() {
        sessionDidChange()
    }

    func logout() {
        cancelCurrentOperation()
        sessionController.logout()
        route = .authentication
    }

    func waitForIdle() async {
        await operationTask?.value
    }

    private func restoreAndRoute() {
        cancelCurrentOperation()
        route = .loading
        let token = generation
        operationTask = Task { [weak self] in
            await self?.restoreAndReconcile(token: token)
        }
    }

    private func reconcile(session: AuthenticationSession) {
        cancelCurrentOperation()
        let token = generation
        operationTask = Task { [weak self] in
            await self?.performReconciliation(session: session, token: token)
        }
    }

    private func restoreAndReconcile(token: UUID) async {
        await sessionController.restoreSession()
        guard isCurrent(token: token) else { return }
        guard let session = sessionController.authenticationSession() else {
            route = .authentication
            return
        }
        await performReconciliation(session: session, token: token)
    }

    private func performReconciliation(
        session: AuthenticationSession,
        token: UUID
    ) async {
        guard isCurrent(token: token, session: session) else { return }

        let localSourceKind: BootstrapSourceKind
        do {
            localSourceKind = try resolveSourceKind(for: session)
        } catch {
            route = .reconciling(.needsAttention("bootstrap_account_mismatch"))
            return
        }

        route = .loading
        do {
            let bootstrap = try await loadOrCreateStatus(localSourceKind: localSourceKind)
            guard isCurrent(token: token, session: session) else { return }
            if apply(
                bootstrap.status,
                session: session,
                sourceKind: bootstrap.sourceKind
            ) {
                return
            }

            if let pipeline {
                let completedStatus = try await pipeline.run(
                    initialStatus: bootstrap.status,
                    session: session,
                    sourceKind: bootstrap.sourceKind
                ) { [weak self] status in
                    guard let self, self.isCurrent(token: token, session: session) else {
                        return
                    }
                    if bootstrap.sourceKind != .newInstall {
                        self.route = .reconciling(.working(status))
                    }
                }
                guard isCurrent(token: token, session: session) else { return }
                _ = apply(
                    completedStatus,
                    session: session,
                    sourceKind: bootstrap.sourceKind
                )
                return
            }

            let resumedStatus = try await api.resume(
                sourceKind: bootstrap.sourceKind,
                vaultCheckpoint: nil
            )
            guard isCurrent(token: token, session: session) else { return }
            _ = apply(
                resumedStatus,
                session: session,
                sourceKind: bootstrap.sourceKind
            )
        } catch is CancellationError {
            return
        } catch let error as AccountBootstrapPipelineError {
            guard isCurrent(token: token, session: session) else { return }
            switch error {
            case let .retryable(code):
                route = .reconciling(.retryable(code))
            case let .needsAttention(code):
                route = .reconciling(.needsAttention(code))
            }
        } catch let error as APIError {
            guard isCurrent(token: token, session: session) else { return }
            if error.code == "bootstrap_conflict" || error.statusCode == 409 {
                route = .reconciling(.needsAttention(error.code ?? "bootstrap_conflict"))
            } else {
                route = .reconciling(.retryable(error.code ?? "bootstrap_temporarily_unavailable"))
            }
        } catch {
            guard isCurrent(token: token, session: session) else { return }
            route = .reconciling(.retryable("bootstrap_temporarily_unavailable"))
        }
    }

    private func loadOrCreateStatus(
        localSourceKind: BootstrapSourceKind
    ) async throws -> (status: AccountBootstrapStatus, sourceKind: BootstrapSourceKind) {
        do {
            let status = try await api.status()
            return (status, status.sourceKind)
        } catch let error as APIError where error.code == "bootstrap_not_found" {
            let status = try await api.resume(
                sourceKind: localSourceKind,
                vaultCheckpoint: nil
            )
            return (status, status.sourceKind)
        }
    }

    private func apply(
        _ status: AccountBootstrapStatus,
        session: AuthenticationSession,
        sourceKind: BootstrapSourceKind
    ) -> Bool {
        let checkpoint = BootstrapCheckpoint(
            accountID: session.accountID,
            vaultID: session.vaultID,
            sourceKind: sourceKind,
            updatedAt: status.updatedAt
        )
        try? checkpointStore.save(checkpoint)

        switch status.overall {
        case .complete:
            route = .diary(accountID: session.accountID, vaultID: session.vaultID)
            return true
        case let .needsAttention(code):
            route = .reconciling(.needsAttention(code))
            return true
        case .pending, .running:
            route = sourceKind == .newInstall ? .loading : .reconciling(.working(status))
            return false
        }
    }

    private func resolveSourceKind(
        for session: AuthenticationSession
    ) throws -> BootstrapSourceKind {
        if let checkpoint = try checkpointStore.load() {
            guard checkpoint.accountID == session.accountID,
                  checkpoint.vaultID == session.vaultID
            else {
                if noticeController.hasLegacyData {
                    throw BootstrapCoordinatorError.accountMismatch
                }
                return .newInstall
            }
            return checkpoint.sourceKind
        }
        return noticeController.hasLegacyData ? .legacyLocal : .newInstall
    }

    private func cancelCurrentOperation() {
        generation = UUID()
        operationTask?.cancel()
        operationTask = nil
    }

    private func isCurrent(
        token: UUID,
        session: AuthenticationSession? = nil
    ) -> Bool {
        guard generation == token, !Task.isCancelled else {
            return false
        }
        guard let session else {
            return true
        }
        let current = sessionController.authenticationSession()
        return current?.accountID == session.accountID && current?.vaultID == session.vaultID
    }
}

private enum BootstrapCoordinatorError: Error {
    case accountMismatch
}

extension ApplicationSessionController: BootstrapSessionControlling {}
