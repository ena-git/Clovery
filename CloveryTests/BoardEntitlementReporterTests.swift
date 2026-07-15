import XCTest
@testable import Clovery

@MainActor
final class BoardEntitlementReporterTests: XCTestCase {
    func testRestoreSuppressesUpdatesUntilOutcomeCompletesThenReplaysLatestEntitlement() async {
        var currentEntitlement = false
        var reportedEvents: [String] = []
        var resumeRestore: CheckedContinuation<Void, Never>?
        let restoreStarted = expectation(description: "restore started")
        let reporter = BoardEntitlementReporter(
            currentEntitlement: { currentEntitlement },
            reportUnlock: { reportedEvents.append("unlock:\($0)") }
        )

        let restoreTask = Task { @MainActor in
            await reporter.reportRestore(
                performRestore: {
                    restoreStarted.fulfill()
                    await withCheckedContinuation { continuation in
                        resumeRestore = continuation
                    }
                    return "notFound"
                },
                reportOutcome: { outcome in
                    reportedEvents.append("outcome:\(outcome)")
                }
            )
        }

        await fulfillment(of: [restoreStarted], timeout: 0.5)
        currentEntitlement = true
        reporter.reportObservedEntitlement(true)
        XCTAssertEqual(reportedEvents, [])

        resumeRestore?.resume()
        await restoreTask.value

        XCTAssertEqual(reportedEvents, ["outcome:notFound", "unlock:true"])
        XCTAssertFalse(reporter.isSuppressingObservedEntitlements)
    }

    func testRestoreOutcomeFailureRestoresObservationAndReplaysLatestEntitlement() async {
        var currentEntitlement = true
        var reportedEntitlements: [Bool] = []
        let reporter = BoardEntitlementReporter(
            currentEntitlement: { currentEntitlement },
            reportUnlock: { reportedEntitlements.append($0) }
        )

        await reporter.reportRestore(
            performRestore: { "restored" },
            reportOutcome: { _ in throw ReporterTestError.javascriptFailed }
        )

        XCTAssertEqual(reportedEntitlements, [true])
        XCTAssertFalse(reporter.isSuppressingObservedEntitlements)

        currentEntitlement = false
        reporter.reportObservedEntitlement(false)
        XCTAssertEqual(reportedEntitlements, [true, false])
    }

    func testRestoreOutcomeCancellationRestoresObservationAndReplaysLatestEntitlement() async {
        var currentEntitlement = true
        var reportedEntitlements: [Bool] = []
        let restoreStarted = expectation(description: "restore started")
        let reporter = BoardEntitlementReporter(
            currentEntitlement: { currentEntitlement },
            reportUnlock: { reportedEntitlements.append($0) }
        )

        let restoreTask = Task { @MainActor in
            await reporter.reportRestore(
                performRestore: { () async throws -> String in
                    restoreStarted.fulfill()
                    while !Task.isCancelled {
                        await Task.yield()
                    }
                    throw CancellationError()
                },
                reportOutcome: { _ in XCTFail("cancelled restore must not report an outcome") }
            )
        }

        await fulfillment(of: [restoreStarted], timeout: 0.5)
        restoreTask.cancel()
        await restoreTask.value

        XCTAssertEqual(reportedEntitlements, [true])
        XCTAssertFalse(reporter.isSuppressingObservedEntitlements)

        currentEntitlement = false
        reporter.reportObservedEntitlement(false)
        XCTAssertEqual(reportedEntitlements, [true, false])
    }
}

private enum ReporterTestError: Error {
    case javascriptFailed
}
