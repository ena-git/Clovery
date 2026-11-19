import SwiftUI
import CoreText

// ═══════════════════════════════════════════
// MARK: - Theme (mirrors PALETTES / DARK_PALETTES in the iPhone app)
// ═══════════════════════════════════════════
struct WP {
    let bg: Color, paper: Color, accent: Color, accentDark: Color, accentSoft: Color
    let ink: Color, inkSoft: Color, inkMut: Color
    let accentRGB: (Double, Double, Double)
    let dark: Bool

    /// Text drawn on top of the accent colour (white, or near-black for very light accents such as 纸墨 dark).
    var onAccent: Color {
        let l = 0.299 * accentRGB.0 + 0.587 * accentRGB.1 + 0.114 * accentRGB.2
        return l > 0.72 ? Color(red: 0.07, green: 0.07, blue: 0.07) : .white
    }

    private static func h(_ v: Int) -> (Double, Double, Double) {
        (Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }
    private static func col(_ t: (Double, Double, Double)) -> Color { Color(red: t.0, green: t.1, blue: t.2) }
    private static func make(bg: Int, paper: Int, ink: Int, soft: Int, mut: Int,
                             accent: Int, accentDark: Int, accentSoft: Int, dark: Bool) -> WP {
        WP(bg: col(h(bg)), paper: col(h(paper)), accent: col(h(accent)), accentDark: col(h(accentDark)),
           accentSoft: col(h(accentSoft)), ink: col(h(ink)), inkSoft: col(h(soft)), inkMut: col(h(mut)),
           accentRGB: h(accent), dark: dark)
    }

    static func g(_ k: String, dark: Bool) -> WP {
        if dark {
            switch k {
            case "sakura": return make(bg: 0x18100F, paper: 0x221818, ink: 0xF0E4E6, soft: 0xB8A0A6, mut: 0x7A6268, accent: 0xE68DA6, accentDark: 0xC87090, accentSoft: 0x2E1820, dark: true)
            case "ocean":  return make(bg: 0x0C1418, paper: 0x141E24, ink: 0xE0ECF0, soft: 0x96AEB6, mut: 0x5C7880, accent: 0x5BB8C5, accentDark: 0x40909E, accentSoft: 0x152428, dark: true)
            case "kraft":  return make(bg: 0x141208, paper: 0x1E1A10, ink: 0xEAE2D0, soft: 0xB0A484, mut: 0x7A6E50, accent: 0x8C9A50, accentDark: 0x70803A, accentSoft: 0x242218, dark: true)
            case "zhimo":  return make(bg: 0x0A0A0A, paper: 0x141414, ink: 0xF0F0F0, soft: 0xAAAAAA, mut: 0x666666, accent: 0xE8E8E8, accentDark: 0xFFFFFF, accentSoft: 0x2A2A2A, dark: true)
            default:       return make(bg: 0x0F1410, paper: 0x1A2018, ink: 0xE8EFE5, soft: 0xA5B0A0, mut: 0x6E7A6A, accent: 0x7FC586, accentDark: 0x5FA45F, accentSoft: 0x1F2F1F, dark: true)
            }
        } else {
            switch k {
            case "sakura": return make(bg: 0xFCF7F5, paper: 0xFFFFFF, ink: 0x2A1E22, soft: 0x6A5A60, mut: 0xB5A8AC, accent: 0xE68DA6, accentDark: 0xB85B7A, accentSoft: 0xFBE4ED, dark: false)
            case "ocean":  return make(bg: 0xF5F9FA, paper: 0xFFFFFF, ink: 0x152128, soft: 0x54676D, mut: 0x9BAEB4, accent: 0x5BA8B5, accentDark: 0x34717D, accentSoft: 0xD9ECEF, dark: false)
            case "kraft":  return make(bg: 0xF4EEDF, paper: 0xFBF6E9, ink: 0x2C2418, soft: 0x6E6047, mut: 0xB4A580, accent: 0x7C8A47, accentDark: 0x566430, accentSoft: 0xE8E5C9, dark: false)
            case "zhimo":  return make(bg: 0xF5F5F0, paper: 0xFFFFFF, ink: 0x111111, soft: 0x444444, mut: 0x888888, accent: 0x111111, accentDark: 0x000000, accentSoft: 0xE8E8E8, dark: false)
            default:       return make(bg: 0xFAFAF6, paper: 0xFFFFFF, ink: 0x1A2418, soft: 0x5A655A, mut: 0xA0AC9F, accent: 0x7BB576, accentDark: 0x517D4D, accentSoft: 0xE2EFDF, dark: false)
            }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Fonts (same selection logic as the iPhone widget / app)
// ═══════════════════════════════════════════
enum WFont {
    /// The font files live in the app bundle under fonts/; watchOS has no UIAppFonts array via build settings,
    /// so register them once at launch.
    static func registerBundledFonts() {
        guard let dir = Bundle.main.url(forResource: "fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension.lowercased() == "ttf" || url.pathExtension.lowercased() == "otf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func postScript(font: String, lang: String, bold: Bool) -> String {
        switch font {
        case "NotoSerifSC": return "NotoSerifSC-ExtraLight"
        case "NaiChaTi": return "BoBoNaiChaTi"
        default:
            if lang == "zh" || lang == "zh-TW" { return "YLHZYS" }
            if lang == "ja" { return "Yomogi-Regular" }
            return bold ? "Gaegu-Bold" : "Gaegu-Regular"
        }
    }

    static func make(_ font: String, _ lang: String, _ size: CGFloat, bold: Bool = false) -> Font {
        switch font {
        case "System": return .system(size: size, weight: bold ? .bold : .regular, design: .rounded)
        case "Serif": return .system(size: size, weight: bold ? .semibold : .regular, design: .serif)
        case "NotoSerifSC": return .custom(postScript(font: font, lang: lang, bold: bold), size: size).weight(bold ? .semibold : .regular)
        default: return .custom(postScript(font: font, lang: lang, bold: bold), size: size)
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Vector clover
// ═══════════════════════════════════════════
struct HeartLeaf: Shape {
    func path(in rect: CGRect) -> Path {
        let L = min(rect.width, rect.height)
        let r = L * 0.308
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + L, y: rect.minY + L))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY + L))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + L - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + L - 2 * r, y: rect.minY + L - 2 * r))
        p.addLine(to: CGPoint(x: rect.minX + L - 2 * r, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + L - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct HeartClover: View {
    let size: CGFloat
    let colors: [Color]   // top-left, top-right, bottom-right, bottom-left
    var body: some View {
        let h = size / 2
        ZStack {
            HeartLeaf().fill(colors[0]).frame(width: h, height: h).position(x: h / 2, y: h / 2)
            HeartLeaf().fill(colors[1]).frame(width: h, height: h).scaleEffect(x: -1, y: 1).position(x: h + h / 2, y: h / 2)
            HeartLeaf().fill(colors[2]).frame(width: h, height: h).scaleEffect(x: -1, y: -1).position(x: h + h / 2, y: h + h / 2)
            HeartLeaf().fill(colors[3]).frame(width: h, height: h).scaleEffect(x: 1, y: -1).position(x: h / 2, y: h + h / 2)
        }
        .frame(width: size, height: size)
    }
}

/// Brand-green clover with a short stem.
struct CloverSprig: View {
    let size: CGFloat
    private func shade(_ k: Double) -> Color {
        Color(red: min(1, 0.66 * k), green: min(1, 0.83 * k), blue: min(1, 0.38 * k))
    }
    var body: some View {
        ZStack(alignment: .top) {
            Path { p in
                p.move(to: CGPoint(x: size * 0.5, y: size * 0.78))
                p.addQuadCurve(to: CGPoint(x: size * 0.56, y: size * 1.12), control: CGPoint(x: size * 0.46, y: size * 0.98))
            }
            .stroke(shade(0.78), style: StrokeStyle(lineWidth: max(1, size * 0.07), lineCap: .round))
            .frame(width: size, height: size * 1.15)
            HeartClover(size: size * 0.9, colors: [shade(1.0), shade(1.08), shade(0.92), shade(0.84)])
                .frame(width: size, height: size * 0.9)
        }
        .frame(width: size, height: size * 1.15)
    }
}

/// Four overlapping circles – the same quatrefoil used by the iPhone widgets.
struct Quatrefoil: Shape {
    func path(in rect: CGRect) -> Path {
        let S = min(rect.width, rect.height)
        let r = S * 0.32, o = S * 0.18
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for (dx, dy) in [(-o, -o), (o, -o), (o, o), (-o, o)] {
            p.addEllipse(in: CGRect(x: c.x + dx - r, y: c.y + dy - r, width: 2 * r, height: 2 * r))
        }
        return p
    }
}
