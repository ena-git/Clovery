import Foundation

@main
struct BoardEntitlementReporterRegressionTests {
    @MainActor
    static func main() async {
        var currentEntitlement = false
        var events: [String] = []
        let reporter = BoardEntitlementReporter(
            currentEntitlement: { currentEntitlement },
            reportUnlock: { events.append("unlock:\($0)") }
        )

        await reporter.reportRestoreOutcome {
            events.append("outcome")
            await Task.yield()
            currentEntitlement = true
            reporter.reportObservedEntitlement(true)
            events.append("outcome-complete")
        }

        expect(events, ["outcome", "outcome-complete", "unlock:true"])
        expect(reporter.isSuppressingObservedEntitlements, false)

        await reporter.reportRestoreOutcome {
            throw ReporterTestError.javascriptFailed
        }

        expect(events, ["outcome", "outcome-complete", "unlock:true", "unlock:true"])
        expect(reporter.isSuppressingObservedEntitlements, false)
    }

    private static func expect<T: Equatable>(
        _ actual: T,
        _ expected: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard actual == expected else {
            fatalError("Expected \(expected), got \(actual)", file: file, line: line)
        }
    }
}

private enum ReporterTestError: Error {
    case javascriptFailed
}
