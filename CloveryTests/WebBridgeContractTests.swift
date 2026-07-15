import Foundation
import XCTest
@testable import Clovery

final class WebBridgeContractTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testPhotoAndSyncHandlersAreRegistered() throws {
        let webViewSource = try source("Clovery/WebView.swift")

        for handler in [
            "photoSave", "photoLoad", "photoGC", "icloud", "cloudkit", "migrationExport",
            "openAppSettings"
        ] {
            XCTAssertTrue(
                webViewSource.contains("config.userContentController.add(context.coordinator, name: \"\(handler)\")"),
                "Missing registered handler: \(handler)"
            )
        }
    }

    func testPhotoCallbacksUseStructuredBridgeJavaScript() throws {
        let webViewSource = try source("Clovery/WebView.swift")
        let bridgeSource = try source("Clovery/BridgeJavaScript.swift")

        XCTAssertTrue(webViewSource.contains("BridgeJavaScript.photoLoaded(reqId: reqId, base64: base64)"))
        XCTAssertTrue(webViewSource.contains("BridgeJavaScript.photoSaveFailed(filename: filename, code: code)"))
        XCTAssertTrue(bridgeSource.contains("window.__cloveryPhotoLoaded"))
        XCTAssertTrue(bridgeSource.contains("window.__cloveryPhotoSaveFailed"))
        XCTAssertTrue(bridgeSource.contains("JSONSerialization.data(withJSONObject:"))
    }

    func testHTMLRollsBackFailedPhotoAndOffersLoadRetry() throws {
        let html = try source("Clovery/Clover Diary.html")

        XCTAssertTrue(html.contains("window.__cloveryPhotoSaveFailed = (filename, code) =>"))
        XCTAssertTrue(html.contains("clovery-photo-save-failed"))
        XCTAssertTrue(html.contains("照片未保存，请重试"))
        XCTAssertTrue(html.contains("retryPhotoLoad"))
    }

    func testPhotoPermissionRecoveryOpensSettingsWithoutDirectPhotoWrites() throws {
        let webViewSource = try source("Clovery/WebView.swift")
        let html = try source("Clovery/Clover Diary.html")

        XCTAssertTrue(webViewSource.contains("message.name == \"openAppSettings\""))
        XCTAssertTrue(webViewSource.contains("handleOpenAppSettings()"))
        XCTAssertTrue(html.contains("messageHandlers?.openAppSettings?.postMessage"))
        XCTAssertTrue(html.contains("minHeight:44"))
        XCTAssertFalse(webViewSource.contains("PHPhotoLibrary.shared().performChanges"))
    }

    func testOpenAppSettingsRoutesToImageExporter() {
        let imageExporter = ImageExportingSpy()
        let coordinator = WebView.Coordinator(imageExporter: imageExporter)

        coordinator.handleOpenAppSettings()

        XCTAssertEqual(imageExporter.openSettingsCount, 1)
    }

    @MainActor
    func testCloudKitPullSkipsContainerWhenUnavailable() async {
        let completed = expectation(description: "CloudKit fallback completed")
        var receivedEntries: [[String: Any]]?
        let sync = CloudKitSync(isAvailable: { false })

        sync.pullAll(photosDir: FileManager.default.temporaryDirectory) { entries in
            receivedEntries = entries
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(receivedEntries?.count, 0)
    }

    func testMigrationExportIsUserTriggeredAndReportsCounts() throws {
        let webViewSource = try source("Clovery/WebView.swift")
        let bridgeSource = try source("Clovery/BridgeJavaScript.swift")
        let html = try source("Clovery/Clover Diary.html")

        XCTAssertTrue(webViewSource.contains("deletedIDsJSON: deletedIDsJSON"))
        XCTAssertTrue(webViewSource.contains("MigrationBundleExporter().export("))
        XCTAssertTrue(webViewSource.contains("BridgeJavaScript.migrationExportResult("))
        XCTAssertTrue(bridgeSource.contains("window.__cloveryMigrationExportResult"))
        XCTAssertTrue(html.contains("window.__cloveryMigrationExportResult = result =>"))
        XCTAssertTrue(html.contains("为迁移导出数据"))
        XCTAssertTrue(html.contains("messageHandlers?.migrationExport?.postMessage"))
        XCTAssertTrue(html.contains("deletedIDs: localStorage.getItem('clovery_deleted_ids') || '[]'"))
    }

    func testBoardEntitlementLifecycleAndRestoreFeedbackContract() throws {
        let webViewSource = try source("Clovery/WebView.swift")
        let appSource = try source("Clovery/CloveryApp.swift")
        let html = try source("Clovery/Clover Diary.html")

        XCTAssertTrue(webViewSource.contains("startObservingBoardStore()"))
        XCTAssertTrue(appSource.contains("refreshBoardEntitlement()"))
        XCTAssertTrue(html.contains("window._boardRestoreResult = (outcome) =>"))
        XCTAssertTrue(html.contains("购买请求正在等待批准"))
        XCTAssertTrue(html.contains("没有找到可恢复的购买记录"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}

private final class ImageExportingSpy: ImageExporting {
    private(set) var openSettingsCount = 0

    func handle(
        action: String,
        dataURL: String,
        saveCompletion: @escaping (PhotoSaveOutcome) -> Void
    ) {}

    func openSettings() {
        openSettingsCount += 1
    }
}
