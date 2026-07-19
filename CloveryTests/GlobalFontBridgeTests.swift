import XCTest
@testable import Clovery

@MainActor
final class GlobalFontBridgeTests: XCTestCase {
    func testWebFontPayloadUpdatesNativeFontStore() {
        let primary = UserDefaults(
            suiteName: "GlobalFontBridgeTests.primary.\(UUID())"
        )!
        let fallback = UserDefaults(
            suiteName: "GlobalFontBridgeTests.fallback.\(UUID())"
        )!
        let store = AppFontStore(
            primaryDefaults: primary,
            fallbackDefaults: fallback
        )
        let coordinator = WebView.Coordinator(fontStore: store)

        coordinator.handleFontPreference("NotoSerifSC")

        XCTAssertEqual(store.selection, .notoSerifSC)
        XCTAssertEqual(
            primary.string(forKey: AppFontStorageKey.selection),
            "NotoSerifSC"
        )
    }
}
