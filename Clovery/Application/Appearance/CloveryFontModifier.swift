import SwiftUI
import UIKit

enum CloveryFontRole {
    case title
    case action
    case body
    case caption

    var pointSize: CGFloat {
        switch self {
        case .title: 48
        case .action, .body: 24
        case .caption: 16
        }
    }

    var textStyle: UIFont.TextStyle {
        switch self {
        case .title: .largeTitle
        case .action: .title3
        case .body: .body
        case .caption: .caption1
        }
    }
}

struct CloveryFontResolver {
    typealias FontLoader = (_ name: String, _ size: CGFloat) -> UIFont?

    private let loadFont: FontLoader

    init(loadFont: @escaping FontLoader = { UIFont(name: $0, size: $1) }) {
        self.loadFont = loadFont
    }

    func uiFont(
        for selection: AppFontSelection,
        role: CloveryFontRole
    ) -> UIFont {
        let baseFont: UIFont
        if selection == .system {
            baseFont = UIFont.systemFont(ofSize: role.pointSize)
        } else {
            baseFont = customFont(for: selection, size: role.pointSize) ??
                UIFont.systemFont(ofSize: role.pointSize)
        }
        return UIFontMetrics(forTextStyle: role.textStyle).scaledFont(for: baseFont)
    }

    private func customFont(
        for selection: AppFontSelection,
        size: CGFloat
    ) -> UIFont? {
        let fonts = postScriptNames(for: selection).compactMap {
            loadFont($0, size)
        }
        guard let primary = fonts.first else {
            return nil
        }
        guard fonts.count > 1 else {
            return primary
        }
        let descriptor = primary.fontDescriptor.addingAttributes([
            .cascadeList: fonts.dropFirst().map(\.fontDescriptor)
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    private func postScriptNames(
        for selection: AppFontSelection
    ) -> [String] {
        switch selection {
        case .handwriting:
            ["YLHZYS", "Gaegu-Regular", "Yomogi-Regular"]
        case .system:
            []
        case .notoSerifSC:
            ["NotoSerifSC-ExtraLight", "STSongti-SC-Regular"]
        case .naiChaTi:
            ["BoBoNaiChaTi", "YLHZYS", "Gaegu-Regular"]
        }
    }
}

private struct AppFontSelectionEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppFontSelection.handwriting
}

extension EnvironmentValues {
    var appFontSelection: AppFontSelection {
        get { self[AppFontSelectionEnvironmentKey.self] }
        set { self[AppFontSelectionEnvironmentKey.self] = newValue }
    }
}

private struct CloveryFontModifier: ViewModifier {
    @Environment(\.appFontSelection) private var selection
    let role: CloveryFontRole
    private let resolver = CloveryFontResolver()

    func body(content: Content) -> some View {
        content.font(Font(resolver.uiFont(for: selection, role: role)))
    }
}

extension View {
    func cloveryFont(_ role: CloveryFontRole) -> some View {
        modifier(CloveryFontModifier(role: role))
    }
}
