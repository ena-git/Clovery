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

    private let languageCode: String
    private let loadFont: FontLoader

    init(
        languageCode: String = Locale.preferredLanguages.first ?? "en",
        loadFont: @escaping FontLoader = { UIFont(name: $0, size: $1) }
    ) {
        self.languageCode = languageCode
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased() ?? "en"
        self.loadFont = loadFont
    }

    func uiFont(
        for selection: AppFontSelection,
        role: CloveryFontRole,
        contentSizeCategory: UIContentSizeCategory = .large
    ) -> UIFont {
        let baseFont: UIFont
        if selection == .system {
            baseFont = UIFont.systemFont(ofSize: role.pointSize)
        } else {
            baseFont = customFont(for: selection, size: role.pointSize) ??
                UIFont.systemFont(ofSize: role.pointSize)
        }
        let traits = UITraitCollection(
            preferredContentSizeCategory: contentSizeCategory
        )
        return UIFontMetrics(forTextStyle: role.textStyle).scaledFont(
            for: baseFont,
            compatibleWith: traits
        )
    }

    private func customFont(
        for selection: AppFontSelection,
        size: CGFloat
    ) -> UIFont? {
        guard let plan = fontPlan(for: selection),
              let primary = loadFont(plan.primary, size) else {
            return nil
        }

        let cascadeFonts = plan.cascade.compactMap { loadFont($0, size) }
        guard !cascadeFonts.isEmpty else {
            return primary
        }
        let descriptor = primary.fontDescriptor.addingAttributes([
            .cascadeList: cascadeFonts.map(\.fontDescriptor)
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    private func fontPlan(
        for selection: AppFontSelection
    ) -> (primary: String, cascade: [String])? {
        switch selection {
        case .handwriting:
            let names: [String]
            switch languageCode {
            case "zh":
                names = ["YLHZYS", "Gaegu-Regular", "Yomogi-Regular"]
            case "ja":
                names = ["Yomogi-Regular", "YLHZYS", "Gaegu-Regular"]
            default:
                names = ["Gaegu-Regular", "YLHZYS", "Yomogi-Regular"]
            }
            return (names[0], Array(names.dropFirst()))
        case .system:
            return nil
        case .notoSerifSC:
            return ("NotoSerifSC-ExtraLight", ["STSongti-SC-Regular"])
        case .naiChaTi:
            return ("BoBoNaiChaTi", ["YLHZYS", "Gaegu-Regular"])
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let role: CloveryFontRole
    private let resolver = CloveryFontResolver()

    func body(content: Content) -> some View {
        content.font(
            Font(
                resolver.uiFont(
                    for: selection,
                    role: role,
                    contentSizeCategory: dynamicTypeSize.uiContentSizeCategory
                )
            )
        )
    }
}

private extension DynamicTypeSize {
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall:
            .extraSmall
        case .small:
            .small
        case .medium:
            .medium
        case .large:
            .large
        case .xLarge:
            .extraLarge
        case .xxLarge:
            .extraExtraLarge
        case .xxxLarge:
            .extraExtraExtraLarge
        case .accessibility1:
            .accessibilityMedium
        case .accessibility2:
            .accessibilityLarge
        case .accessibility3:
            .accessibilityExtraLarge
        case .accessibility4:
            .accessibilityExtraExtraLarge
        case .accessibility5:
            .accessibilityExtraExtraExtraLarge
        @unknown default:
            .large
        }
    }
}

extension View {
    func cloveryFont(_ role: CloveryFontRole) -> some View {
        modifier(CloveryFontModifier(role: role))
    }
}
