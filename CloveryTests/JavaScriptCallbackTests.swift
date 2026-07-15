import Foundation
import XCTest
@testable import Clovery

final class JavaScriptCallbackTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testBridgeEscapesMultipleArgumentsAndNull() {
        XCTAssertEqual(
            BridgeJavaScript.photoLoaded(reqId: "id'\\\n", base64: nil),
            #"window.__cloveryPhotoLoaded?.("id'\\\n",null);"#
        )
        XCTAssertEqual(
            BridgeJavaScript.photoSaveFailed(filename: "photo-1.jpg", code: "ioError"),
            #"window.__cloveryPhotoSaveFailed?.("photo-1.jpg","ioError");"#
        )
    }

    func testRestoreResultUsesStructuredCallback() {
        XCTAssertEqual(
            BridgeJavaScript.boardRestoreResult(.notFound),
            #"window._boardRestoreResult?.("notFound");"#
        )
    }

    func testAllWebViewCallbacksUseBridgeJavaScript() throws {
        let source = try read("Clovery/WebView.swift")
        let bridgeSource = try read("Clovery/BridgeJavaScript.swift")

        XCTAssertFalse(source.contains(#"\\("#))
        XCTAssertFalse(source.contains("var d = "))
        XCTAssertTrue(source.contains("BridgeJavaScript.iCloudData(dataObj)"))
        XCTAssertTrue(bridgeSource.contains("evaluateJSONCallback(name: String, payload: [Any])"))
    }

    func testCloudKitLogsInterpolateRealErrorsAndRecordIDs() throws {
        let source = try read("Clovery/CloudKitSync.swift")

        XCTAssertFalse(source.contains(#"\\("#))
        XCTAssertTrue(source.contains(#"push failed for \(id): \(error.localizedDescription)"#))
        XCTAssertTrue(source.contains(#"photo copy failed for \(record.recordID.recordName)"#))
    }

    private func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
