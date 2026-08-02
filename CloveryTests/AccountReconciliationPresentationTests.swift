import Foundation
import XCTest
@testable import Clovery

final class AccountReconciliationPresentationTests: XCTestCase {
    func testSupportReferenceIsShortStableAndContainsNoRawCode() {
        let code = "apple_transaction_account_mismatch"
        let reference = BootstrapSupportReference.make(code)

        XCTAssertEqual(reference, BootstrapSupportReference.make(code))
        XCTAssertEqual(reference.count, 8)
        XCTAssertFalse(reference.contains(code))
    }

    func testPresentationIncludesAllStagesAndAccessibilityContracts() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Clovery/Features/Bootstrap/Presentation/AccountReconciliationView.swift"
            ),
            encoding: .utf8
        )

        for text in [
            "正在整理你的 Clovery",
            "正在确认账户",
            "正在安全保存日记与照片",
            "正在恢复已购权益",
            "正在同步云端内容",
            "重试",
            "退出账户",
            "联系支持"
        ] {
            XCTAssertTrue(source.contains(text))
        }
        XCTAssertTrue(source.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(source.contains("reduceMotionOverride ?? systemReduceMotion"))
        XCTAssertTrue(source.contains(".cloveryFont("))
        XCTAssertTrue(source.contains(".accessibilityLabel("))
        XCTAssertTrue(source.contains("ScrollView"))
        XCTAssertFalse(source.contains("accountID"))
        XCTAssertFalse(source.contains("transactionID"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
