import Foundation

@main
struct V1BridgeRegressionTests {
    static func main() {
        expect(
            BridgeJavaScript.boardUnlockStatus(true),
            "window._boardUnlockStatus?.(true);"
        )
        expect(
            BridgeJavaScript.boardPurchaseResult(.success),
            #"window._boardPurchaseResult?.("success");"#
        )
        expect(
            BridgeJavaScript.boardPriceResult("CN¥6'\\\n"),
            #"window._boardPriceResult?.("CN¥6'\\\n");"#
        )
        expect(
            BridgeJavaScript.photoSaveResult(.permissionDenied),
            #"window.__clovery_imageSaveResult?.("permissionDenied");"#
        )
        expect(BoardPurchaseOutcome.cancelled.rawValue, "cancelled")
        expect(BoardPurchaseOutcome.pending.rawValue, "pending")
        expect(BoardPurchaseOutcome.failed.rawValue, "failed")
        expect(PhotoSaveOutcome.invalidImage.rawValue, "invalidImage")
    }

    private static func expect(
        _ actual: String,
        _ expected: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard actual == expected else {
            fatalError("Expected \(expected), got \(actual)", file: file, line: line)
        }
    }
}
