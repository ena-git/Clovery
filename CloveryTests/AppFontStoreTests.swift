import XCTest
@testable import Clovery

@MainActor
final class AppFontStoreTests: XCTestCase {
    private var primarySuiteName: String!
    private var fallbackSuiteName: String!
    private var primaryDefaults: UserDefaults!
    private var fallbackDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        primarySuiteName = "com.clovery.tests.font.primary.\(UUID().uuidString)"
        fallbackSuiteName = "com.clovery.tests.font.fallback.\(UUID().uuidString)"
        primaryDefaults = UserDefaults(suiteName: primarySuiteName)
        fallbackDefaults = UserDefaults(suiteName: fallbackSuiteName)
    }

    override func tearDown() {
        primaryDefaults.removePersistentDomain(forName: primarySuiteName)
        fallbackDefaults.removePersistentDomain(forName: fallbackSuiteName)
        primaryDefaults = nil
        fallbackDefaults = nil
        primarySuiteName = nil
        fallbackSuiteName = nil
        super.tearDown()
    }

    func testLegacyWidgetValueMigratesFromFallbackDefaults() {
        fallbackDefaults.set(
            AppFontSelection.notoSerifSC.rawValue,
            forKey: AppFontStorageKey.widgetCompatibility
        )

        let store = makeStore()

        XCTAssertEqual(store.selection, .notoSerifSC)
        assertMirrored(.notoSerifSC)
    }

    func testInitializationUsesDocumentedDefaultsPrecedence() {
        primaryDefaults.set(
            AppFontSelection.system.rawValue,
            forKey: AppFontStorageKey.widgetCompatibility
        )
        fallbackDefaults.set(
            AppFontSelection.naiChaTi.rawValue,
            forKey: AppFontStorageKey.selection
        )

        let store = makeStore()

        XCTAssertEqual(store.selection, .system)
        assertMirrored(.system)
    }

    func testUpdatePublishesAndMirrorsCanonicalAndLegacyKeys() {
        let store = makeStore()

        store.update(rawValue: AppFontSelection.naiChaTi.rawValue)

        XCTAssertEqual(store.selection, .naiChaTi)
        assertMirrored(.naiChaTi)
    }

    func testUnknownUpdateRestoresHandwritingAndMirrorsIt() {
        let store = makeStore()
        store.update(rawValue: AppFontSelection.system.rawValue)

        store.update(rawValue: "UnknownFont")

        XCTAssertEqual(store.selection, .handwriting)
        assertMirrored(.handwriting)
    }

    private func makeStore() -> AppFontStore {
        AppFontStore(
            primaryDefaults: primaryDefaults,
            fallbackDefaults: fallbackDefaults
        )
    }

    private func assertMirrored(
        _ selection: AppFontSelection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for defaults in [primaryDefaults!, fallbackDefaults!] {
            XCTAssertEqual(
                defaults.string(forKey: AppFontStorageKey.selection),
                selection.rawValue,
                file: file,
                line: line
            )
            XCTAssertEqual(
                defaults.string(forKey: AppFontStorageKey.widgetCompatibility),
                selection.rawValue,
                file: file,
                line: line
            )
        }
    }
}
