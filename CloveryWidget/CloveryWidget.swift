import WidgetKit
import SwiftUI

// ═══════════════════════════════════════════
// MARK: - Data
// ═══════════════════════════════════════════

struct DiaryEntry: Codable {
    let id: String?
    let date: String?
    let lucky: String?
    let mood: String?
    let isWelcome: Bool?
    let tags: [String]?
}

struct CD {
    let entries: [DiaryEntry]
    let name: String
    let streak: Int
    let todayEntries: [DiaryEntry]
    let uniqueDays: [String]
    let totalClovers: Int
    let leafCount: Int
    let fontName: String
    let palette: String
    let lang: String
    let darkPref: Bool

    static func load() -> CD {
        let s = UserDefaults(suiteName: "group.com.clovery.app")
        let name = s?.string(forKey: "widget_name") ?? ""
        let raw = s?.string(forKey: "widget_entries") ?? "[]"
        let fontName = s?.string(forKey: "widget_font") ?? "Gaegu"
        let palette = s?.string(forKey: "widget_palette") ?? "clover"
        let lang = s?.string(forKey: "widget_lang") ?? "zh"
        let darkPref = s?.bool(forKey: "widget_dark") ?? false
        var all: [DiaryEntry] = []
        if let data = raw.data(using: .utf8) {
            all = (try? JSONDecoder().decode([DiaryEntry].self, from: data)) ?? []
        }
        let real = all.filter { $0.isWelcome != true }
        let today = tStr()
        let days = Array(Set(real.compactMap { $0.date })).sorted()
        let dc = days.count
        return CD(
            entries: real,
            name: name,
            streak: stk(Set(days), today),
            todayEntries: real.filter { $0.date == today },
            uniqueDays: days,
            totalClovers: dc / 4,
            leafCount: dc % 4,
            fontName: fontName,
            palette: palette,
            lang: lang,
            darkPref: darkPref
        )
    }

    static func tStr() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: Date())
    }

    static func stk(_ days: Set<String>, _ today: String) -> Int {
        let c = Calendar.current
        let n = Date()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        let o = days.contains(today) ? 0 : 1
        guard let first = c.date(byAdding: .day, value: -o, to: n),
              days.contains(f.string(from: first)) else {
            return 0
        }
        var s = 0
        while let day = c.date(byAdding: .day, value: -(o + s), to: n),
              days.contains(f.string(from: day)) {
            s += 1
        }
        return s
    }

    var ps: String {
        switch fontName {
        case "System", "Serif", "NotoSerifSC":
            return ""
        case "NaiChaTi":
            return "BoBoNaiChaTi"
        default:
            if lang == "zh" { return "YLHZYS" }
            if lang == "ja" { return "Yomogi-Regular" }
            return "Gaegu-Regular"
        }
    }

    var psB: String {
        switch fontName {
        case "System", "Serif", "NotoSerifSC":
            return ""
        case "NaiChaTi":
            return "BoBoNaiChaTi"
        default:
            if lang == "zh" { return "YLHZYS" }
            if lang == "ja" { return "Yomogi-Regular" }
            return "Gaegu-Bold"
        }
    }
}

func af(_ d: CD, _ sz: CGFloat, bold: Bool = false) -> Font {
    if d.fontName == "System" {
        return .system(size: sz, weight: bold ? .bold : .regular, design: .rounded)
    }
    if d.fontName == "Serif" || d.fontName == "NotoSerifSC" {
        return .system(size: sz, weight: bold ? .bold : .regular, design: .serif)
    }
    return .custom(bold ? d.psB : d.ps, size: sz)
}

// ═══════════════════════════════════════════
// MARK: - Palette
// ═══════════════════════════════════════════

struct P {
    let bg: Color
    let paper: Color
    let accent: Color
    let accentSoft: Color
    let ink: Color
    let inkSoft: Color
    let inkMut: Color
    let meadowTop: Color
    let meadowBot: Color

    static func g(_ k: String, dark: Bool = false) -> P {
        if dark {
            switch k {
            case "sakura":
                return P(
                    bg: c(24, 16, 15), paper: c(38, 25, 24),
                    accent: c(224, 134, 160), accentSoft: c(66, 39, 47),
                    ink: c(246, 236, 238), inkSoft: c(194, 174, 178), inkMut: c(128, 108, 114),
                    meadowTop: c(24, 34, 28), meadowBot: c(17, 26, 20)
                )
            case "ocean":
                return P(
                    bg: c(12, 20, 24), paper: c(21, 33, 40),
                    accent: c(96, 178, 192), accentSoft: c(27, 52, 60),
                    ink: c(232, 242, 246), inkSoft: c(162, 184, 192), inkMut: c(104, 126, 134),
                    meadowTop: c(18, 34, 36), meadowBot: c(12, 24, 26)
                )
            case "kraft":
                return P(
                    bg: c(20, 18, 8), paper: c(34, 30, 16),
                    accent: c(146, 162, 84), accentSoft: c(52, 54, 28),
                    ink: c(244, 236, 214), inkSoft: c(186, 172, 140), inkMut: c(124, 112, 86),
                    meadowTop: c(28, 34, 20), meadowBot: c(20, 26, 14)
                )
            default:
                return P(
                    bg: c(15, 20, 16), paper: c(25, 34, 27),
                    accent: c(123, 181, 118), accentSoft: c(34, 54, 36),
                    ink: c(236, 244, 234), inkSoft: c(170, 188, 168), inkMut: c(106, 124, 106),
                    meadowTop: c(24, 38, 28), meadowBot: c(16, 28, 20)
                )
            }
        }
        switch k {
        case "sakura":
            return P(
                bg: c(252, 247, 245), paper: .white,
                accent: c(230, 141, 166), accentSoft: c(251, 228, 237),
                ink: c(42, 30, 34), inkSoft: c(106, 90, 96), inkMut: c(181, 168, 172),
                meadowTop: c(244, 238, 236), meadowBot: c(232, 242, 232)
            )
        case "ocean":
            return P(
                bg: c(245, 249, 250), paper: .white,
                accent: c(91, 168, 181), accentSoft: c(217, 236, 239),
                ink: c(21, 33, 40), inkSoft: c(84, 103, 109), inkMut: c(155, 174, 180),
                meadowTop: c(226, 242, 244), meadowBot: c(204, 228, 224)
            )
        case "kraft":
            return P(
                bg: c(244, 238, 223), paper: c(251, 246, 233),
                accent: c(124, 138, 71), accentSoft: c(232, 229, 201),
                ink: c(44, 36, 24), inkSoft: c(110, 96, 71), inkMut: c(180, 165, 128),
                meadowTop: c(236, 236, 214), meadowBot: c(214, 222, 190)
            )
        default:
            return P(
                bg: c(250, 250, 246), paper: .white,
                accent: c(123, 181, 118), accentSoft: c(226, 239, 223),
                ink: c(26, 36, 24), inkSoft: c(90, 101, 90), inkMut: c(160, 172, 159),
                meadowTop: c(223, 240, 232), meadowBot: c(181, 204, 187)
            )
        }
    }

    private static func c(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

// ═══════════════════════════════════════════
// MARK: - Images
// ═══════════════════════════════════════════

struct CloverImg: View {
    let size: CGFloat
    var body: some View {
        if let u = Bundle.main.url(forResource: "clover", withExtension: "png"),
           let d = try? Data(contentsOf: u),
           let i = UIImage(data: d) {
            Image(uiImage: i)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Text("🍀").font(.system(size: size * 0.7))
        }
    }
}

struct LeafImg: View {
    let size: CGFloat
    let on: Bool
    var body: some View {
        if let u = Bundle.main.url(forResource: "leaf", withExtension: "png"),
           let d = try? Data(contentsOf: u),
           let i = UIImage(data: d) {
            Image(uiImage: i)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .saturation(on ? 1 : 0)
                .opacity(on ? 1 : 0.35)
                .brightness(on ? 0 : 0.12)
        } else {
            Circle()
                .fill(on ? P.g("clover").accent : Color.gray.opacity(0.3))
                .frame(width: size, height: size)
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Timeline
// ═══════════════════════════════════════════

struct CTE: TimelineEntry {
    let date: Date
    let data: CD
}

struct CPr: TimelineProvider {
    func placeholder(in context: Context) -> CTE { CTE(date: .now, data: .load()) }
    func getSnapshot(in context: Context, completion: @escaping (CTE) -> Void) {
        completion(CTE(date: .now, data: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CTE>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [CTE(date: .now, data: .load())], policy: .after(next)))
    }
}

// ═══════════════════════════════════════════
// MARK: - 1. Quick Write (Small) — app homepage
// ═══════════════════════════════════════════

struct W1: View {
    @Environment(\.colorScheme) private var colorScheme
    let d: CD
    var p: P { P.g(d.palette, dark: colorScheme == .dark || d.darkPref) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 2)
            ZStack {
                let sz: CGFloat = 72
                let off: CGFloat = 13
                Circle().fill(p.accent).frame(width: sz, height: sz).offset(x: -off, y: -off)
                Circle().fill(p.accent).frame(width: sz, height: sz).offset(x: off, y: -off)
                Circle().fill(p.accent).frame(width: sz, height: sz).offset(x: -off, y: off)
                Circle().fill(p.accent).frame(width: sz, height: sz).offset(x: off, y: off)
                VStack(spacing: 2) {
                    if let lucky = d.todayEntries.first?.lucky, !lucky.isEmpty {
                        Text(d.lang == "zh" ? "今天的幸运" : d.lang == "ja" ? "今日のラッキー" : d.lang == "ko" ? "오늘의 행운" : "today's luck")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .tracking(1)
                        Text(lucky)
                            .font(af(d, 11))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    } else {
                        CloverImg(size: 20)
                        Text(
                            d.lang == "zh" ? "今天最幸运的小事\n是什么？"
                            : d.lang == "ja" ? "今日のラッキーは？"
                            : d.lang == "ko" ? "오늘의 행운은?"
                            : "What's your\nlucky moment?"
                        )
                        .font(af(d, 11))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineSpacing(1)
                        Text(d.lang == "zh" ? "轻触记录" : d.lang == "ja" ? "タップして記録" : d.lang == "ko" ? "탭하여 기록" : "tap to write")
                            .font(af(d, 9))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            .shadow(color: p.accent.opacity(0.18), radius: 10, y: 4)

            RoundedRectangle(cornerRadius: 1)
                .fill(p.inkMut.opacity(0.4))
                .frame(width: 2.5, height: 14)
                .padding(.top, -1)
            Spacer(minLength: 2)
            Text(
                d.lang == "zh" ? "连续 \(d.streak) 天 · \(d.entries.count) 条记录"
                : d.lang == "ja" ? "\(d.streak)日連続 · \(d.entries.count)件"
                : d.lang == "ko" ? "\(d.streak)일 연속 · \(d.entries.count)개"
                : "\(d.streak) days · \(d.entries.count) entries"
            )
            .font(af(d, 11))
            .foregroundStyle(p.inkMut)
            Spacer(minLength: 4)
        }
        .widgetURL(URL(string: "clovery://write"))
    }
}

// ═══════════════════════════════════════════
// MARK: - 2. Leaf Progress (Small) — growing clover
// ═══════════════════════════════════════════

struct W2: View {
    @Environment(\.colorScheme) private var colorScheme
    let d: CD
    var p: P { P.g(d.palette, dark: colorScheme == .dark || d.darkPref) }

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 2)
            let sz: CGFloat = 42
            let off: CGFloat = 8
            ZStack {
                LeafImg(size: sz, on: d.leafCount > 0).rotationEffect(.degrees(-45)).offset(x: -off, y: -off)
                LeafImg(size: sz, on: d.leafCount > 1).rotationEffect(.degrees(45)).offset(x: off, y: -off)
                LeafImg(size: sz, on: d.leafCount > 2).rotationEffect(.degrees(-135)).offset(x: -off, y: off)
                LeafImg(size: sz, on: d.leafCount > 3).rotationEffect(.degrees(135)).offset(x: off, y: off)
            }
            Spacer(minLength: 2)
            HStack(spacing: 0) {
                Text("\(d.leafCount)").font(af(d, 28, bold: true)).foregroundStyle(p.ink)
                Text(" / 4").font(af(d, 16)).foregroundStyle(p.inkMut)
            }
            let remain = 4 - d.leafCount
            if d.leafCount >= 4 {
                Text(d.lang == "zh" ? "四叶草完成啦！🎉" : d.lang == "ja" ? "四つ葉完成！🎉" : d.lang == "ko" ? "네잎클로버 완성! 🎉" : "Clover complete! 🎉")
                    .font(af(d, 12)).foregroundStyle(p.inkSoft)
            } else if d.leafCount == 0 {
                Text(d.lang == "zh" ? "开始收集叶片吧 🌿" : d.lang == "ja" ? "葉っぱを集めよう 🌿" : d.lang == "ko" ? "잎사귀를 모아봐요 🌿" : "Start collecting! 🌿")
                    .font(af(d, 12)).foregroundStyle(p.inkSoft)
            } else {
                Text(
                    d.lang == "zh" ? "还差 \(remain) 片就满啦 🌿"
                    : d.lang == "ja" ? "あと \(remain) 枚で満開 🌿"
                    : d.lang == "ko" ? "\(remain)개 더 모으면 완성 🌿"
                    : "\(remain) more to go 🌿"
                )
                .font(af(d, 12)).foregroundStyle(p.inkSoft)
            }
            Spacer(minLength: 4)
        }
        .widgetURL(URL(string: "clovery://lucky"))
    }
}

// ═══════════════════════════════════════════
// MARK: - 3. Diary (Medium) — calendar + entries
// ═══════════════════════════════════════════

struct W3: View {
    @Environment(\.colorScheme) private var colorScheme
    let d: CD
    var p: P { P.g(d.palette, dark: colorScheme == .dark || d.darkPref) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                let cal = Calendar.current
                let now = Date()
                let y = cal.component(.year, from: now)
                let m = cal.component(.month, from: now)
                Text(d.lang == "zh" || d.lang == "ja" ? "\(y)年\(m)月" : d.lang == "ko" ? "\(y)년 \(m)월" : "\(mn(m)) \(y)")
                    .font(af(d, 13, bold: true))
                    .foregroundStyle(p.ink)
                let monthEntries = d.entries.filter { ($0.date ?? "").hasPrefix(String(format: "%04d-%02d", y, m)) }
                Text(d.lang == "zh" ? "本月 \(monthEntries.count) 篇" : d.lang == "ja" ? "今月 \(monthEntries.count) 件" : d.lang == "ko" ? "이번 달 \(monthEntries.count)개" : "\(monthEntries.count) entries")
                    .font(af(d, 9))
                    .foregroundStyle(p.inkMut)
                    .padding(.bottom, 1)
                MCal(days: Set(d.uniqueDays), p: p, lang: d.lang)
            }
            .frame(width: 128)
            .padding(.leading, 2)

            VStack(spacing: 6) {
                let recent = recentGrouped()
                if recent.isEmpty {
                    Spacer()
                    Text("✨").font(.system(size: 20))
                    Spacer()
                } else {
                    ForEach(Array(recent.prefix(2).enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                let fd = fmtDate(group.date)
                                Text(fd).font(af(d, 11)).foregroundStyle(p.inkSoft)
                                if group.entries.count > 1 {
                                    Text("\(group.entries.count)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 16, height: 16)
                                        .background(Circle().fill(p.accent))
                                }
                                Spacer()
                                Text("›").font(.system(size: 13)).foregroundStyle(p.inkMut)
                            }
                            ForEach(Array(group.entries.prefix(2).enumerated()), id: \.offset) { i, e in
                                if i > 0 {
                                    Rectangle().fill(p.inkMut.opacity(0.15)).frame(height: 0.5).padding(.leading, 2)
                                }
                                Text(e.lucky ?? "").font(af(d, 12)).foregroundStyle(p.ink).lineLimit(1)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(p.paper))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.inkMut.opacity(0.1), lineWidth: 0.5))
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 2)
        }
        .padding(.vertical, 4)
        .widgetURL(URL(string: "clovery://calendar"))
    }

    func recentGrouped() -> [(date: String, entries: [DiaryEntry])] {
        var map: [String: [DiaryEntry]] = [:]
        var order: [String] = []
        for e in d.entries.sorted(by: { ($0.date ?? "") > ($1.date ?? "") }) {
            let dt = e.date ?? ""
            if !map.keys.contains(dt) { order.append(dt) }
            map[dt, default: []].append(e)
        }
        return order.map { (date: $0, entries: map[$0]!) }
    }

    func fmtDate(_ iso: String) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 3 else { return iso }
        let m = parts[1], day = parts[2]
        if d.lang == "zh" || d.lang == "ja" { return "\(m)月\(day)日" }
        if d.lang == "ko" { return "\(m)월 \(day)일" }
        return "\(mn(m)) \(day)"
    }

    func mn(_ m: Int) -> String {
        ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][max(0, min(11, m - 1))]
    }
}

struct MCal: View {
    let days: Set<String>
    let p: P
    let lang: String

    var body: some View {
        let cal = Calendar.current
        let now = Date()
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        let td = cal.component(.day, from: now)
        let first = cal.date(from: DateComponents(year: y, month: m, day: 1))!
        let wd = cal.component(.weekday, from: first) - 1
        let dim = cal.range(of: .day, in: .month, for: first)!.count
        let cells = Array(repeating: 0, count: wd) + Array(1...dim)
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        let wh = lang == "zh" || lang == "ja" ? ["日", "一", "二", "三", "四", "五", "六"] :
            lang == "ko" ? ["일", "월", "화", "수", "목", "금", "토"] : ["S", "M", "T", "W", "T", "F", "S"]
        VStack(spacing: 1) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(wh[i]).font(.system(size: 7, weight: .medium)).foregroundStyle(p.inkMut).frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let day = col < row.count ? row[col] : 0
                        if day == 0 {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 13)
                        } else {
                            let iso = String(format: "%04d-%02d-%02d", y, m, day)
                            let has = days.contains(iso)
                            let isT = day == td
                            VStack(spacing: 1) {
                                ZStack {
                                    if isT { Circle().fill(p.accent).frame(width: 16, height: 16) }
                                    Text("\(day)")
                                        .font(.system(size: 8, weight: isT ? .bold : has ? .semibold : .regular))
                                        .foregroundStyle(isT ? .white : has ? p.ink : p.inkMut)
                                }
                                if has && !isT {
                                    Circle().fill(p.accent).frame(width: 3, height: 3)
                                } else {
                                    Color.clear.frame(height: 3)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 15)
                        }
                    }
                }
            }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - 4. Clover Field (Large) — responsive meadow
// ═══════════════════════════════════════════

struct W4: View {
    @Environment(\.colorScheme) private var colorScheme
    let d: CD
    var showBackground: Bool = true
    var p: P { P.g(d.palette, dark: colorScheme == .dark || d.darkPref) }

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 160)
            let h = max(geo.size.height, 160)
            ZStack {
                if showBackground {
                    LinearGradient(colors: [p.meadowTop, p.meadowBot], startPoint: .top, endPoint: .bottom)
                }

                ForEach(0..<20, id: \.self) { i in
                    let xRatio = CGFloat(((i * 37 + 13) % 86) + 7) / 100
                    let yRatio = CGFloat(((i * 53 + 29) % 72) + 20) / 100
                    let bladeH = CGFloat(((i * 17 + 7) % 12) + 6)
                    let r = Double(((i * 23 + 11) % 20) - 10)
                    Capsule()
                        .fill(p.inkMut.opacity(0.28))
                        .frame(width: 1.5, height: bladeH)
                        .rotationEffect(.degrees(r))
                        .position(x: w * xRatio, y: h * yRatio)
                }

                let total = d.totalClovers
                if total > 0 {
                    ForEach(0..<min(total, 15), id: \.self) { i in
                        let xRatio = CGFloat(((i * 67 + 23) % 78) + 11) / 100
                        let yRatio = CGFloat(((i * 43 + 37) % 58) + 26) / 100
                        let sz = CGFloat(((i * 31 + 11) % 16) + 24)
                        VStack(spacing: 0) {
                            CloverImg(size: sz)
                            Capsule()
                                .fill(p.accent.opacity(0.35))
                                .frame(width: 1.5, height: sz * 0.22)
                        }
                        .position(x: w * xRatio, y: h * yRatio)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(d.lang == "zh" ? "记录你的" : d.lang == "ja" ? "あなたの" : d.lang == "ko" ? "당신의" : "Your")
                        .font(af(d, 12))
                        .foregroundStyle(p.ink.opacity(0.6))
                    Text(d.lang == "zh" ? "幸运" : d.lang == "ja" ? "ラッキー" : d.lang == "ko" ? "행운" : "Lucky")
                        .font(af(d, 22, bold: true))
                        .foregroundStyle(p.ink)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.top, 10)

                if total > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 3) {
                                CloverImg(size: 14)
                                Text("×\(total)")
                                    .font(af(d, 13, bold: true))
                                    .foregroundStyle(p.ink.opacity(0.75))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(p.paper.opacity(0.78)))
                        }
                    }
                    .padding(10)
                }

                if total == 0 && d.leafCount == 0 {
                    VStack(spacing: 4) {
                        CloverImg(size: 36).opacity(0.45)
                        Text(
                            d.lang == "zh" ? "集满四片叶片\n就能长出第一朵四叶草！"
                            : d.lang == "ja" ? "4枚集めて最初の四つ葉を育てよう！"
                            : d.lang == "ko" ? "잎 4개를 모아 첫 클로버를 피워봐요!"
                            : "Grow your first clover!"
                        )
                        .font(af(d, 12))
                        .foregroundStyle(p.ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                    }
                    .offset(y: 16)
                }
            }
        }
        .widgetURL(URL(string: "clovery://lucky"))
    }
}

// ═══════════════════════════════════════════
// MARK: - 5. Lock Screen Widgets (Accessory Families)
// ═══════════════════════════════════════════

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let d: CD

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Gauge(value: Double(d.leafCount), in: 0...4) {
                        Image(systemName: "leaf.fill")
                    } currentValueLabel: {
                        VStack(spacing: 0) {
                            Text("\(d.leafCount)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text("/4")
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .opacity(0.75)
                        }
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .widgetAccentable()
                        Text(headerText)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                    if let lucky = d.todayEntries.first?.lucky, !lucky.isEmpty {
                        Text(lucky)
                            .font(.system(size: 12))
                            .lineLimit(2)
                    } else {
                        Text(emptyPrompt)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryInline:
                if let lucky = d.todayEntries.first?.lucky, !lucky.isEmpty {
                    Label(inlineRecordedText(lucky), systemImage: "leaf.fill")
                } else {
                    Label(inlinePromptText, systemImage: "leaf.fill")
                }
            default:
                EmptyView()
            }
        }
        .widgetURL(URL(string: "clovery://write"))
    }

    private var headerText: String {
        switch d.lang {
        case "zh": return "连续 \(d.streak) 天 · \(d.totalClovers) 朵"
        case "ja": return "\(d.streak)日連続 · \(d.totalClovers)個"
        case "ko": return "\(d.streak)일 연속 · \(d.totalClovers)개"
        default: return "\(d.streak)d streak · \(d.totalClovers) clovers"
        }
    }

    private var emptyPrompt: String {
        switch d.lang {
        case "zh": return "轻触记录今天的小幸运"
        case "ja": return "タップして今日のラッキーを記録"
        case "ko": return "탭하여 오늘의 행운 기록"
        default: return "Tap to record today's luck"
        }
    }

    private func inlineRecordedText(_ lucky: String) -> String {
        switch d.lang {
        case "zh": return "连续\(d.streak)天 · \(lucky)"
        case "ja": return "\(d.streak)日連続 · \(lucky)"
        case "ko": return "\(d.streak)일 · \(lucky)"
        default: return "\(d.streak)d · \(lucky)"
        }
    }

    private var inlinePromptText: String {
        switch d.lang {
        case "zh": return "记录今天的小幸运 (连续\(d.streak)天)"
        case "ja": return "今日のラッキーを記録 (\(d.streak)日)"
        case "ko": return "오늘의 행운 기록 (\(d.streak)일)"
        default: return "Record today's luck (\(d.streak)d)"
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Widget definitions
// ═══════════════════════════════════════════

struct CloveryQuickWriteWidget: Widget {
    let kind = "CloveryQuickWrite"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CPr()) { e in
            ThemedWidgetContainer(data: e.data) {
                W1(d: e.data)
            }
        }
        .configurationDisplayName("小幸运 · 记录")
        .description("轻触开始记录今天的小幸运 🍀")
        .supportedFamilies([.systemSmall])
    }
}

struct CloveryLeafWidget: Widget {
    let kind = "CloveryLeaf"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CPr()) { e in
            ThemedWidgetContainer(data: e.data) {
                W2(d: e.data)
            }
        }
        .configurationDisplayName("小幸运 · 叶片")
        .description("查看四叶草生长进度 🌱")
        .supportedFamilies([.systemSmall])
    }
}

struct CloveryDiaryWidget: Widget {
    let kind = "CloveryDiary"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CPr()) { e in
            ThemedWidgetContainer(data: e.data) {
                W3(d: e.data)
            }
        }
        .configurationDisplayName("小幸运 · 日记")
        .description("日历和最近的幸运记录 📅")
        .supportedFamilies([.systemMedium])
    }
}

struct CloveryFieldWidget: Widget {
    let kind = "CloveryField"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CPr()) { e in
            if #available(iOS 17.0, *) {
                CloveryFieldWidget17View(d: e.data)
            } else {
                W4(d: e.data, showBackground: true)
            }
        }
        .configurationDisplayName("小幸运 · 四叶草田")
        .description("你的四叶草花园 🏡")
        .supportedFamilies([.systemLarge])
    }
}

@available(iOS 17.0, *)
private struct CloveryFieldWidget17View: View {
    @Environment(\.colorScheme) private var colorScheme
    let d: CD

    var body: some View {
        let p = P.g(d.palette, dark: colorScheme == .dark || d.darkPref)
        W4(d: d, showBackground: false)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [p.meadowTop, p.meadowBot], startPoint: .top, endPoint: .bottom)
            }
    }
}

struct CloveryLockScreenWidget: Widget {
    let kind = "CloveryLockScreen"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CPr()) { e in
            if #available(iOS 17.0, *) {
                LockScreenWidgetView(d: e.data)
                    .containerBackground(.clear, for: .widget)
            } else {
                LockScreenWidgetView(d: e.data)
            }
        }
        .configurationDisplayName("小幸运 · 锁屏")
        .description("在锁屏界面查看四叶草进度与今日幸运 🍀")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct ThemedWidgetContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let data: CD
    @ViewBuilder let content: () -> Content

    var body: some View {
        let bg = P.g(data.palette, dark: colorScheme == .dark || data.darkPref).bg
        if #available(iOS 17.0, *) {
            content().containerBackground(bg, for: .widget)
        } else {
            content().background(bg)
        }
    }
}
