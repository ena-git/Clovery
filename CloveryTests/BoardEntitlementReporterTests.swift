import XCTest
@testable import Clovery

@MainActor
final class BoardEntitlementReporterTests: XCTestCase {
    func testRestoreOutcomeCompletesBeforeLatestEntitlementIsReplayed() async {
        var currentEntitlement = false
        var reportedEvents: [String] = []
        var resumeOutcome: CheckedContinuation<Void, Never>?
        let outcomeStarted = expectation(description: "restore outcome reporting started")
        let reporter = BoardEntitlementReporter(
            currentEntitlement: { currentEntitlement },
            reportUnlock: { reportedEvents.append("unlock:\($0)") }
        )

        let restoreTask = Task { @MainActor in
            await reporter.reportRestoreOutcome {
                reportedEvents.append("outcome")
                outcomeStarted.fulfill()
                await withCheckedContinuation { continuation in
                    resumeOutcome = continuation
                }
                reportedEvents.append("outcome-complete")
            }
        }

        await fulfillment(of: [outcomeStarted], timeout: 0.5)
        currentEntitlement = true
        reporter.reportObservedEntitlement(true)
        XCTAssertEqual(reportedEvents, ["outcome"])

        resumeOutcome?.resume()
        await restoreTask.value

        XCTAssertEqual(reportedEvents, ["outcome", "outcome-complete", "unlock:true"])
        XCTAssertFalse(reporter.isSuppressingObservedEntitlements)
    }

    func testRestoreOutcomeFailureRestoresObservationAndReplaysLatestEntitlement() async {
        var currentEntitlement = true
        var reportedEntitlements: [Bool] = []
        let reporter = BoardEntitlementReporter(
            currentEntitlement: { currentEntitlement },
            reportUnlock: { reportedEntitlements.append($0) }
        )

        await reporter.reportRestoreOutcome {
            throw ReporterTestError.javascriptFailed
        }

        XCTAssertEqual(reportedEntitlements, [true])
        XCTAssertFalse(reporter.isSuppressingObservedEntitlements)

        currentEntitlement = false
        reporter.reportObservedEntitlement(false)
        XCTAssertEqual(reportedEntitlements, [true, false])
    }

    func testRestoreOutcomeCancellationRestoresObservationAndReplaysLatestEntitlement() async {
        var currentEntitlement = true
        var reportedEntitlements: [Bool] = []
        let outcomeStarted = expectation(description: "restore outcome reporting started")
        let reporter = BoardEntitlementReporter(
            currentEntitlement: { currentEntitlement },
            reportUnlock: { reportedEntitlements.append($0) }
        )

        let restoreTask = Task { @MainActor in
            await reporter.reportRestoreOutcome {
                outcomeStarted.fulfill()
                while !Task.isCancelled {
                    await Task.yield()
                }
                throw CancellationError()
            }
        }

        await fulfillment(of: [outcomeStarted], timeout: 0.5)
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
