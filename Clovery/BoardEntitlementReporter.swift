@MainActor
final class BoardEntitlementReporter {
    private let currentEntitlement: () -> Bool
    private let reportUnlock: (Bool) -> Void

    private(set) var isSuppressingObservedEntitlements = false

    init(
        currentEntitlement: @escaping () -> Bool,
        reportUnlock: @escaping (Bool) -> Void
    ) {
        self.currentEntitlement = currentEntitlement
        self.reportUnlock = reportUnlock
    }

    func reportObservedEntitlement(_ isUnlocked: Bool) {
        guard !isSuppressingObservedEntitlements else { return }
        reportUnlock(isUnlocked)
    }

    func reportRestoreOutcome(
        _ operation: () async throws -> Void
    ) async {
        await reportRestoreOutcomeWhileSuppressingObservation(operation)
        reportUnlock(currentEntitlement())
    }

    private func reportRestoreOutcomeWhileSuppressingObservation(
        _ operation: () async throws -> Void
    ) async {
        isSuppressingObservedEntitlements = true
        defer { isSuppressingObservedEntitlements = false }

        do {
            try await operation()
        } catch {
        }
    }
}
