import Combine
import Foundation

@MainActor
final class AppFontStore: ObservableObject {
    static let appGroupIdentifier = "group.com.clovery.app"

    @Published private(set) var selection: AppFontSelection

    private let primaryDefaults: UserDefaults
    private let fallbackDefaults: UserDefaults

    init(
        primaryDefaults: UserDefaults? = nil,
        fallbackDefaults: UserDefaults = .standard
    ) {
        self.primaryDefaults = primaryDefaults
            ?? UserDefaults(suiteName: Self.appGroupIdentifier)
            ?? fallbackDefaults
        self.fallbackDefaults = fallbackDefaults

        let storedValue = self.primaryDefaults.string(forKey: AppFontStorageKey.selection)
            ?? self.primaryDefaults.string(forKey: AppFontStorageKey.widgetCompatibility)
            ?? self.fallbackDefaults.string(forKey: AppFontStorageKey.selection)
            ?? self.fallbackDefaults.string(forKey: AppFontStorageKey.widgetCompatibility)
        selection = AppFontSelection(storedValue: storedValue)
        persist(selection)
    }

    func update(rawValue: String?) {
        let updatedSelection = AppFontSelection(storedValue: rawValue)
        selection = updatedSelection
        persist(updatedSelection)
    }

    private func persist(_ selection: AppFontSelection) {
        for defaults in [primaryDefaults, fallbackDefaults] {
            defaults.set(selection.rawValue, forKey: AppFontStorageKey.selection)
            defaults.set(selection.rawValue, forKey: AppFontStorageKey.widgetCompatibility)
        }
    }
}
