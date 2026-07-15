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

        await reporter.reportRestore(
            performRestore: {
                events.append("restore")
                await Task.yield()
                currentEntitlement = true
                reporter.reportObservedEntitlement(true)
                return "notFound"
            },
            reportOutcome: { outcome in
                events.append("outcome:\(outcome)")
            }
        )

        expect(events, ["restore", "outcome:notFound", "unlock:true"])
        expect(reporter.isSuppressingObservedEntitlements, false)

        await reporter.reportRestore(
            performRestore: { "restored" },
            reportOutcome: { _ in throw ReporterTestError.javascriptFailed }
        )

        expect(events, ["restore", "outcome:notFound", "unlock:true", "unlock:true"])
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
