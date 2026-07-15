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

    func reportRestore<Outcome>(
        performRestore: () async throws -> Outcome,
        reportOutcome: (Outcome) async throws -> Void
    ) async {
        await performRestoreWhileSuppressingObservation(
            performRestore: performRestore,
            reportOutcome: reportOutcome
        )
        reportUnlock(currentEntitlement())
    }

    private func performRestoreWhileSuppressingObservation<Outcome>(
        performRestore: () async throws -> Outcome,
        reportOutcome: (Outcome) async throws -> Void
    ) async {
        isSuppressingObservedEntitlements = true
        defer { isSuppressingObservedEntitlements = false }

        do {
            let outcome = try await performRestore()
            try await reportOutcome(outcome)
        } catch {
        }
    }
}
