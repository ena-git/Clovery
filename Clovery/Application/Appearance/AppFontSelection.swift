enum AppFontSelection: String, CaseIterable, Equatable {
    case handwriting = "Gaegu"
    case system = "System"
    case notoSerifSC = "NotoSerifSC"
    case naiChaTi = "NaiChaTi"

    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .handwriting
    }
}

enum AppFontStorageKey {
    static let selection = "clovery_font_selection"
    static let widgetCompatibility = "widget_font"
}
