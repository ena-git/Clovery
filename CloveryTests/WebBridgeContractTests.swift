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
