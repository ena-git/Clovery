import WidgetKit
import SwiftUI

// ═══════════════════════════════════════════
// MARK: - Data
// ═══════════════════════════════════════════

struct DiaryEntry: Codable {
    let id: String?; let date: String?; let lucky: String?
    let mood: String?; let isWelcome: Bool?; let tags: [String]?
    let createdAt: Double?

    /// Mirrors `isRetroactive` in the app: an entry written on a later day than the day it belongs to
    /// does not count towards clovers (field / growing clover / profile), only towards the streak.
    func isRetroactive(using f: DateFormatter) -> Bool {
        var ts = createdAt
        if ts == nil, let id, id.hasPrefix("new-") { ts = Double(id.dropFirst(4)) }
        guard let t = ts, t > 0, let date else { return false }
        return f.string(from: Date(timeIntervalSince1970: t / 1000)) > date
    }
}

struct CD {
    let entries: [DiaryEntry]; let name: String; let streak: Int
    let todayEntries: [DiaryEntry]; let uniqueDays: [String]
    let totalClovers: Int; let leafCount: Int
    let fontName: String; let palette: String; let lang: String; let darkMode: String

    static func load() -> CD {
        let s = UserDefaults(suiteName: "group.com.clovery.app")
        let name = s?.string(forKey: "widget_name") ?? ""
        let raw = s?.string(forKey: "widget_entries") ?? "[]"
        let fontName =
            s?.string(forKey: "clovery_font_selection") ??
            s?.string(forKey: "widget_font") ??
            "Gaegu"
        let palette = s?.string(forKey: "widget_palette") ?? "clover"
        let lang = s?.string(forKey: "widget_lang") ?? "zh"
        let darkMode = s?.string(forKey: "widget_dark") ?? "auto"
        var all: [DiaryEntry] = []
        if let data = raw.data(using: .utf8) { all = (try? JSONDecoder().decode([DiaryEntry].self, from: data)) ?? [] }
        let real = all.filter { $0.isWelcome != true }
        let today = tStr()
        let days = Array(Set(real.compactMap { $0.date })).sorted()
        // Clover growth uses the same rule as the app: one clover per 4 distinct days, ignoring back-filled entries.
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = .current
        let cloverDays = Set(real.filter { !$0.isRetroactive(using: df) }.compactMap { $0.date }).count
        return CD(entries: real, name: name, streak: stk(Set(days), today),
                  todayEntries: real.filter { $0.date == today }, uniqueDays: days,
                  totalClovers: cloverDays/4, leafCount: cloverDays%4, fontName: fontName, palette: palette, lang: lang, darkMode: darkMode)
    }
    static func tStr() -> String { let f=DateFormatter(); f.dateFormat="yyyy-MM-dd"; f.timeZone = .current; return f.string(from:Date()) }
    static func stk(_ days: Set<String>, _ today: String) -> Int {
        let c=Calendar.current,n=Date(),f=DateFormatter(); f.dateFormat="yyyy-MM-dd"; f.timeZone = .current
        let o=days.contains(today) ? 0:1
        if !days.contains(f.string(from:c.date(byAdding:.day,value:-o,to:n)!)){return 0}
        var s=0; while days.contains(f.string(from:c.date(byAdding:.day,value:-(o+s),to:n)!)){s+=1}; return s
    }
    var ps: String {
        switch fontName {
        case "System":
            ""
        case "NotoSerifSC":
            "NotoSerifSC-ExtraLight"
        case "NaiChaTi":
            "BoBoNaiChaTi"
        default:
            lang == "zh" ? "YLHZYS" :
                lang == "ja" ? "Yomogi-Regular" : "Gaegu-Regular"
        }
    }

    var psB: String {
        switch fontName {
        case "System":
            ""
        case "NotoSerifSC":
            "NotoSerifSC-ExtraLight"
        case "NaiChaTi":
            "BoBoNaiChaTi"
        default:
            lang == "zh" ? "YLHZYS" :
                lang == "ja" ? "Yomogi-Regular" : "Gaegu-Bold"
        }
    }

    var isSys: Bool {
        fontName == "System" || fontName == "Serif"
    }
    /// Same rule as the app: an explicit light/dark choice wins, otherwise follow the system.
    func isDark(_ cs: ColorScheme) -> Bool {
        switch darkMode {
        case "dark": return true
        case "light": return false
        default: return cs == .dark
        }
    }
}
func af(_ d:CD,_ sz:CGFloat,bold:Bool=false)->Font{
    if d.fontName == "Serif" { return .system(size:sz,weight:bold ? .semibold:.regular,design:.serif) }
    if d.fontName == "System" { return .system(size:sz,weight:bold ? .bold:.regular,design:.rounded) }
    if d.fontName == "NotoSerifSC" { return .custom(d.ps, size:sz).weight(bold ? .semibold:.regular) }
    return .custom(bold ? d.psB:d.ps, size:sz)
}

// ═══════════════════════════════════════════
// MARK: - Palette
// ═══════════════════════════════════════════
struct P{
    let bg:Color;let paper:Color;let accent:Color;let accentDark:Color;let accentSoft:Color;let ink:Color;let inkSoft:Color;let inkMut:Color
    let bgRGB:(Double,Double,Double);let accentRGB:(Double,Double,Double);let dark:Bool

    /// Text/icons drawn on top of the accent colour (white, or near-black when the accent is very light).
    var onAccent:Color{
        let l=0.299*accentRGB.0+0.587*accentRGB.1+0.114*accentRGB.2
        return l>0.72 ? Color(red:0.07,green:0.07,blue:0.07) : .white
    }
    /// bg tinted towards the accent — used for the meadow / large-widget gradient.
    func tint(_ k:Double)->Color{
        Color(red:bgRGB.0*(1-k)+accentRGB.0*k,green:bgRGB.1*(1-k)+accentRGB.1*k,blue:bgRGB.2*(1-k)+accentRGB.2*k)
    }

    // Values mirror PALETTES / DARK_PALETTES in Clover Diary.html.
    private static func h(_ v:Int)->(Double,Double,Double){(Double((v>>16)&255)/255,Double((v>>8)&255)/255,Double(v&255)/255)}
    private static func col(_ t:(Double,Double,Double))->Color{Color(red:t.0,green:t.1,blue:t.2)}
    private static func make(bg:Int,paper:Int,ink:Int,soft:Int,mut:Int,accent:Int,accentDark:Int,accentSoft:Int,dark:Bool)->P{
        P(bg:col(h(bg)),paper:col(h(paper)),accent:col(h(accent)),accentDark:col(h(accentDark)),accentSoft:col(h(accentSoft)),
          ink:col(h(ink)),inkSoft:col(h(soft)),inkMut:col(h(mut)),bgRGB:h(bg),accentRGB:h(accent),dark:dark)
    }
    static func g(_ k:String, dark:Bool=false)->P{
        if dark {
            switch k {
            case "sakura":return make(bg:0x18100F,paper:0x221818,ink:0xF0E4E6,soft:0xB8A0A6,mut:0x7A6268,accent:0xE68DA6,accentDark:0xC87090,accentSoft:0x2E1820,dark:true)
            case "ocean":return make(bg:0x0C1418,paper:0x141E24,ink:0xE0ECF0,soft:0x96AEB6,mut:0x5C7880,accent:0x5BB8C5,accentDark:0x40909E,accentSoft:0x152428,dark:true)
            case "kraft":return make(bg:0x141208,paper:0x1E1A10,ink:0xEAE2D0,soft:0xB0A484,mut:0x7A6E50,accent:0x8C9A50,accentDark:0x70803A,accentSoft:0x242218,dark:true)
            case "zhimo":return make(bg:0x0A0A0A,paper:0x141414,ink:0xF0F0F0,soft:0xAAAAAA,mut:0x666666,accent:0xE8E8E8,accentDark:0xFFFFFF,accentSoft:0x2A2A2A,dark:true)
            default:return make(bg:0x0F1410,paper:0x1A2018,ink:0xE8EFE5,soft:0xA5B0A0,mut:0x6E7A6A,accent:0x7FC586,accentDark:0x5FA45F,accentSoft:0x1F2F1F,dark:true)
            }
        } else {
            switch k {
            case "sakura":return make(bg:0xFCF7F5,paper:0xFFFFFF,ink:0x2A1E22,soft:0x6A5A60,mut:0xB5A8AC,accent:0xE68DA6,accentDark:0xB85B7A,accentSoft:0xFBE4ED,dark:false)
            case "ocean":return make(bg:0xF5F9FA,paper:0xFFFFFF,ink:0x152128,soft:0x54676D,mut:0x9BAEB4,accent:0x5BA8B5,accentDark:0x34717D,accentSoft:0xD9ECEF,dark:false)
            case "kraft":return make(bg:0xF4EEDF,paper:0xFBF6E9,ink:0x2C2418,soft:0x6E6047,mut:0xB4A580,accent:0x7C8A47,accentDark:0x566430,accentSoft:0xE8E5C9,dark:false)
            case "zhimo":return make(bg:0xF5F5F0,paper:0xFFFFFF,ink:0x111111,soft:0x444444,mut:0x888888,accent:0x111111,accentDark:0x000000,accentSoft:0xE8E8E8,dark:false)
            default:return make(bg:0xFAFAF6,paper:0xFFFFFF,ink:0x1A2418,soft:0x5A655A,mut:0xA0AC9F,accent:0x7BB576,accentDark:0x517D4D,accentSoft:0xE2EFDF,dark:false)
            }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Timeline
// ═══════════════════════════════════════════
struct CTE:TimelineEntry{let date:Date;let data:CD}
struct CPr:TimelineProvider{
    func placeholder(in c:Context)->CTE{CTE(date:.now,data:.load())}
    func getSnapshot(in c:Context,completion:@escaping(CTE)->Void){completion(CTE(date:.now,data:.load()))}
    func getTimeline(in c:Context,completion:@escaping(Timeline<CTE>)->Void){
        completion(Timeline(entries:[CTE(date:.now,data:.load())],policy:.after(Calendar.current.date(byAdding:.minute,value:30,to:.now)!)))
    }
}

// ═══════════════════════════════════════════
// MARK: - Vector clover pieces (no bitmap assets needed in the widget bundle)
// ═══════════════════════════════════════════

/// One heart-leaf quadrant (top-left). The seam sits at the bottom-right corner of its square;
/// flip it to build the other three leaves.
struct HeartLeaf: Shape {
    func path(in rect: CGRect) -> Path {
        let L = min(rect.width, rect.height)
        let r = L * 0.308                       // bump radius (bump width = 0.616 L)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + L, y: rect.minY + L))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY + L))
        // left bump (bottom → left → top)
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + L - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + L - 2 * r, y: rect.minY + L - 2 * r))
        p.addLine(to: CGPoint(x: rect.minX + L - 2 * r, y: rect.minY + r))
        // top bump (left → top → right)
        p.addArc(center: CGPoint(x: rect.minX + L - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// Four heart leaves meeting at the centre. `colors` order: top-left, top-right, bottom-right, bottom-left.
struct HeartClover: View {
    let size: CGFloat
    let colors: [Color]
    var seam: Double = 0.0
    var body: some View {
        let h = size / 2
        ZStack {
            HeartLeaf().fill(colors[0]).frame(width: h, height: h).position(x: h / 2, y: h / 2)
            HeartLeaf().fill(colors[1]).frame(width: h, height: h).scaleEffect(x: -1, y: 1)
                .position(x: h + h / 2, y: h / 2)
            HeartLeaf().fill(colors[2]).frame(width: h, height: h).scaleEffect(x: -1, y: -1)
                .position(x: h + h / 2, y: h + h / 2)
            HeartLeaf().fill(colors[3]).frame(width: h, height: h).scaleEffect(x: 1, y: -1)
                .position(x: h / 2, y: h + h / 2)
            if seam > 0 {
                let r = h * 0.308
                Rectangle().fill(Color.black.opacity(seam)).frame(width: max(1, size * 0.006), height: size - 2 * r)
                    .position(x: h, y: h)
                Rectangle().fill(Color.black.opacity(seam)).frame(width: size - 2 * r, height: max(1, size * 0.006))
                    .position(x: h, y: h)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Small clover with a stem, in the three tints used by the design (fresh / pale / deep).
struct CloverSprig: View {
    enum Tint { case fresh, pale, deep }
    let size: CGFloat
    var tint: Tint = .fresh
    private var base: (Double, Double, Double) {
        switch tint {
        case .fresh: return (0.66, 0.83, 0.38)
        case .pale:  return (0.86, 0.96, 0.58)
        case .deep:  return (0.42, 0.62, 0.27)
        }
    }
    private func shade(_ k: Double) -> Color {
        Color(red: min(1, base.0 * k), green: min(1, base.1 * k), blue: min(1, base.2 * k))
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

// ═══════════════════════════════════════════
// MARK: - 1. Quick Write (Small) — big quatrefoil
// ═══════════════════════════════════════════
struct W1: View {
    let d: CD
    @Environment(\.colorScheme) var cs
    var p: P { P.g(d.palette, dark: d.isDark(cs)) }

    var body: some View {
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let S = min(W * 0.84, H - 30)          // quatrefoil span
            let r = S * 0.32                        // circle radius
            let o = S * 0.18                        // circle centre offset
            VStack(spacing: 0) {
                ZStack {
                    ForEach(0..<4, id: \.self) { i in
                        Circle().fill(p.accent)
                            .frame(width: r * 2, height: r * 2)
                            .offset(x: i % 2 == 0 ? -o : o, y: i < 2 ? -o : o)
                    }
                    content(S)
                }
                .frame(width: S, height: S)
                .shadow(color: p.accent.opacity(0.22), radius: 8, y: 3)

                // stem
                Path { st in
                    st.move(to: CGPoint(x: 2, y: 0))
                    st.addQuadCurve(to: CGPoint(x: 2, y: 9), control: CGPoint(x: 5, y: 4.5))
                }
                .stroke(p.inkSoft.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 6, height: 9)
                .padding(.top, 1)

                Spacer(minLength: 1)

                HStack(spacing: 4) {
                    Text(verbatim: d.lang == "zh" || d.lang == "ja" ? "连续 \(d.streak) 天" : d.lang == "ko" ? "연속 \(d.streak)일" : "\(d.streak) days")
                    Circle().fill(p.inkMut).frame(width: 3, height: 3)
                    Text(verbatim: d.lang == "zh" ? "\(d.entries.count) 条记录" : d.lang == "ja" ? "\(d.entries.count) 件" : d.lang == "ko" ? "\(d.entries.count)개" : "\(d.entries.count) entries")
                }
                .font(af(d, 10.5, bold: true))
                .foregroundStyle(p.inkSoft)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: W)
            }
            .frame(width: W, height: H, alignment: .top)
        }
    }

    @ViewBuilder
    func content(_ S: CGFloat) -> some View {
        let tw = S * 0.66
        if let lucky = d.todayEntries.first?.lucky, !lucky.isEmpty {
            VStack(spacing: 3) {
                Text(d.lang == "zh" ? "今天的幸运" : d.lang == "ja" ? "今日のラッキー" : d.lang == "ko" ? "오늘의 행운" : "today's luck")
                    .font(af(d, 8.5)).foregroundStyle(p.onAccent.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.7)
                Text(lucky).font(af(d, 11)).foregroundStyle(p.onAccent)
                    .lineLimit(3).minimumScaleFactor(0.7).multilineTextAlignment(.center)
            }
            .frame(width: tw)
        } else {
            VStack(spacing: 3) {
                CloverSprig(size: S * 0.12, tint: .fresh)
                Text(d.lang == "zh" ? "今天最幸运的小事\n是什么？" : d.lang == "ja" ? "今日のラッキーは？" : d.lang == "ko" ? "오늘의 행운은?" : "What's your\nlucky moment?")
                    .font(af(d, 9.5)).foregroundStyle(p.onAccent)
                    .multilineTextAlignment(.center).lineSpacing(1)
                    .lineLimit(2).minimumScaleFactor(0.7)
                Text(d.lang == "zh" ? "轻触记录" : d.lang == "ja" ? "タップして記録" : d.lang == "ko" ? "탭해서 기록" : "tap to write")
                    .font(af(d, 8.5)).foregroundStyle(p.onAccent.opacity(0.6))
                    .lineLimit(1).minimumScaleFactor(0.7).padding(.top, 1)
            }
            .frame(width: tw)
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - 2. Leaf Progress (Small) — heart-leaf clover
// ═══════════════════════════════════════════
struct W2: View {
    let d: CD
    @Environment(\.colorScheme) var cs
    var p: P { P.g(d.palette, dark: d.isDark(cs)) }

    var body: some View {
        let on = d.palette == "clover"
            ? Color(red: 0.592, green: 0.773, blue: 0.490)
            : p.accent
        let off = p.dark ? p.paper.opacity(1) : Color(red: 0.76, green: 0.76, blue: 0.75)
        let n = d.leafCount
        // top-left, top-right, bottom-right, bottom-left
        let colors: [Color] = (0..<4).map { $0 < n ? on : off }

        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            let S = min(W * 0.64, H * 0.56)
            VStack(spacing: 0) {
                HeartClover(size: S, colors: colors, seam: p.dark ? 0.25 : 0.10)
                    .shadow(color: on.opacity(n > 0 ? 0.18 : 0), radius: 8, y: 2)
                    .padding(.top, 2)
                Spacer(minLength: 2)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: "\(n)").font(af(d, 22, bold: true)).foregroundStyle(p.ink)
                    Text("/ 4").font(af(d, 13)).foregroundStyle(p.inkMut)
                }
                let remain = 4 - n
                Group {
                    if n >= 4 {
                        Text(d.lang == "zh" ? "四叶草完成啦！🎉" : d.lang == "ja" ? "四つ葉が完成！🎉" : d.lang == "ko" ? "네잎클로버 완성! 🎉" : "Clover complete! 🎉")
                    } else if n == 0 {
                        Text(d.lang == "zh" ? "开始收集叶片吧 🌿" : d.lang == "ja" ? "葉っぱを集めよう 🌿" : d.lang == "ko" ? "잎을 모아봐요 🌿" : "Start collecting! 🌿")
                    } else {
                        Text(d.lang == "zh" ? "还差 \(remain) 片就满啦 🌿" : d.lang == "ja" ? "あと\(remain)枚で完成 🌿" : d.lang == "ko" ? "\(remain)장 남았어요 🌿" : "\(remain) more to go 🌿")
                    }
                }
                .font(af(d, 11)).foregroundStyle(p.inkSoft)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.top, 1)
                Spacer(minLength: 2)
            }
            .frame(width: W, height: H)
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - 3. Diary (Medium) — calendar + entries
// ═══════════════════════════════════════════
struct W3: View {
    let d: CD
    @Environment(\.colorScheme) var cs
    var p: P { P.g(d.palette, dark: d.isDark(cs)) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            calendarColumn.frame(maxWidth: .infinity)
            cardsColumn.frame(maxWidth: .infinity)
        }
    }

    // ── left: month calendar ──
    var calendarColumn: some View {
        let cal = Calendar.current, now = Date()
        let y = cal.component(.year, from: now), m = cal.component(.month, from: now)
        let monthEntries = d.entries.filter { ($0.date ?? "").hasPrefix(String(format: "%04d-%02d", y, m)) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("‹").font(.system(size: 13, weight: .regular)).foregroundStyle(p.inkMut)
                Spacer(minLength: 0)
                Text(verbatim: d.lang == "zh" || d.lang == "ja" ? "\(y)年\(m)月" : d.lang == "ko" ? "\(y)년 \(m)월" : "\(mn(m)) \(y)")
                    .font(af(d, 13, bold: true)).foregroundStyle(p.ink).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Text("›").font(.system(size: 13, weight: .regular)).foregroundStyle(p.inkMut)
            }
            .padding(.horizontal, 6)
            Text(verbatim: d.lang == "zh" ? "本月 \(monthEntries.count) 篇" : d.lang == "ja" ? "今月 \(monthEntries.count) 件" : d.lang == "ko" ? "이번 달 \(monthEntries.count)개" : "\(monthEntries.count) this month")
                .font(af(d, 9.5, bold: true)).foregroundStyle(p.inkSoft).padding(.top, 1).padding(.bottom, 2)
            MCal(days: Set(d.uniqueDays), p: p, lang: d.lang, d: d)
        }
    }

    // ── right: recent entry cards ──
    var cardsColumn: some View {
        let recent = recentGrouped()
        return VStack(spacing: 6) {
            if recent.isEmpty {
                Spacer()
                Text("✨").font(.system(size: 22))
                Text(d.lang == "zh" ? "还没有记录" : "No entries yet").font(af(d, 11)).foregroundStyle(p.inkMut)
                Spacer()
            } else {
                ForEach(Array(recent.prefix(2).enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(fmtDate(group.date)).font(af(d, 10.5, bold: true)).foregroundStyle(p.inkSoft)
                                .lineLimit(1).minimumScaleFactor(0.7).fixedSize(horizontal: true, vertical: false)
                            if group.entries.count > 1 {
                                Text(verbatim: "\(group.entries.count)")
                                    .font(.system(size: 8, weight: .bold)).foregroundStyle(p.accentDark)
                                    .frame(width: 15, height: 15).background(Circle().fill(p.accentSoft))
                            }
                            Spacer(minLength: 0)
                            Text("›").font(.system(size: 11)).foregroundStyle(p.inkMut)
                        }
                        ForEach(Array(group.entries.prefix(2).enumerated()), id: \.offset) { i, e in
                            if i > 0 {
                                Line().stroke(p.inkMut.opacity(0.35), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                                    .frame(height: 0.5)
                            }
                            Text(e.lucky ?? "").font(af(d, 11.5)).foregroundStyle(p.ink)
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                    }
                    .padding(.horizontal, 9).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.paper))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(p.inkMut.opacity(0.18), lineWidth: 0.5))
                }
                Spacer(minLength: 0)
            }
        }
    }

    func recentGrouped() -> [(date: String, entries: [DiaryEntry])] {
        var map: [String: [DiaryEntry]] = [:]
        var order: [String] = []
        for e in d.entries.sorted(by: { ($0.date ?? "") > ($1.date ?? "") }) {
            let dt = e.date ?? ""; if !map.keys.contains(dt) { order.append(dt) }
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
    func mn(_ m: Int) -> String { ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][m - 1] }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)); return p
    }
}

struct MCal: View {
    let days: Set<String>; let p: P; let lang: String; let d: CD
    var body: some View {
        let cal = Calendar.current, now = Date()
        let y = cal.component(.year, from: now), m = cal.component(.month, from: now), td = cal.component(.day, from: now)
        let first = cal.date(from: DateComponents(year: y, month: m, day: 1))!
        let wd = cal.component(.weekday, from: first) - 1 // Sun = 0
        let dim = cal.range(of: .day, in: .month, for: first)!.count
        let cells = Array(repeating: 0, count: wd) + Array(1...dim)
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        let wh = lang == "zh" || lang == "ja" ? ["日", "一", "二", "三", "四", "五", "六"] :
                 lang == "ko" ? ["일", "월", "화", "수", "목", "금", "토"] : ["S", "M", "T", "W", "T", "F", "S"]
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(wh[i]).font(af(d, 8.5)).foregroundStyle(p.inkMut).frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 1)
            GeometryReader { g in
                let rowH = g.size.height / CGFloat(max(rows.count, 5))
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                let day = col < row.count ? row[col] : 0
                                if day == 0 {
                                    Color.clear.frame(maxWidth: .infinity)
                                } else {
                                    let iso = String(format: "%04d-%02d-%02d", y, m, day)
                                    let has = days.contains(iso), isT = day == td, future = day > td
                                    VStack(spacing: 1) {
                                        ZStack {
                                            if isT { Circle().fill(p.accent).frame(width: 16, height: 16) }
                                            Text("\(day)")
                                                .font(af(d, 9.5, bold: has || isT))
                                                .foregroundStyle(isT ? p.onAccent : future ? p.inkMut.opacity(0.45) : has ? p.ink : p.inkMut)
                                        }
                                        .frame(height: 16)
                                        Circle().fill(has && !isT ? p.accent : .clear).frame(width: 3, height: 3)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .frame(height: rowH)
                    }
                }
            }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - 4. Clover Field (Large) — meadow
// ═══════════════════════════════════════════
struct MeadowBG: View {
    let palette: String; let darkMode: String
    @Environment(\.colorScheme) var cs
    var body: some View {
        let dark: Bool = darkMode == "dark" ? true : (darkMode == "light" ? false : cs == .dark)
        let p = P.g(palette, dark: dark)
        LinearGradient(colors: dark ? [p.tint(0.12), p.tint(0.04)] : [p.tint(0.18), p.tint(0.38)], startPoint: .top, endPoint: .bottom)
    }
}

struct GrassStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

struct W4: View {
    let d: CD
    @Environment(\.colorScheme) var cs
    var p: P { P.g(d.palette, dark: d.isDark(cs)) }

    // slot positions (fraction of width/height) — first three follow the design
    static let slots: [(CGFloat, CGFloat)] = [
        (0.44, 0.29), (0.82, 0.50), (0.89, 0.88), (0.22, 0.46), (0.62, 0.66), (0.30, 0.80),
        (0.12, 0.66), (0.70, 0.30), (0.56, 0.90), (0.46, 0.52), (0.92, 0.28), (0.10, 0.90)
    ]
    static let grass: [(CGFloat, CGFloat, CGFloat)] = [
        (0.37, 0.29, 22), (0.24, 0.39, 24), (0.60, 0.37, 22), (0.81, 0.38, 16), (0.48, 0.55, 14),
        (0.84, 0.56, 18), (0.05, 0.67, 14), (0.15, 0.82, 22), (0.29, 0.82, 16), (0.73, 0.86, 14),
        (0.53, 0.95, 18), (0.96, 0.90, 20)
    ]
    static let sizes: [CGFloat] = [20, 30, 38, 26, 34, 24, 32, 22, 36, 28, 30, 26]

    var body: some View {
        let total = d.totalClovers
        GeometryReader { g in
            let W = g.size.width, H = g.size.height
            ZStack(alignment: .topLeading) {
                // grass strokes
                ForEach(0..<W4.grass.count, id: \.self) { i in
                    let gr = W4.grass[i]
                    GrassStroke()
                        .stroke((p.dark ? Color.white : p.accentDark).opacity(p.dark ? 0.10 : 0.22),
                                style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .frame(width: 5, height: gr.2)
                        .position(x: W * gr.0, y: H * gr.1)
                }

                // clovers
                ForEach(0..<min(total, W4.slots.count), id: \.self) { i in
                    let s = W4.slots[i]
                    let tint: CloverSprig.Tint = i % 3 == 0 ? .fresh : (i % 3 == 1 ? .pale : .deep)
                    CloverSprig(size: W4.sizes[i], tint: tint)
                        .rotationEffect(.degrees(Double((i * 37) % 24) - 12))
                        .position(x: W * s.0, y: H * s.1)
                }

                // header
                VStack(alignment: .leading, spacing: 0) {
                    Text(d.lang == "zh" ? "记录你的" : d.lang == "ja" ? "あなたの" : d.lang == "ko" ? "당신의" : "Your")
                        .font(af(d, 13)).foregroundStyle(p.inkSoft)
                    Text(d.lang == "zh" ? "幸运" : d.lang == "ja" ? "ラッキー" : d.lang == "ko" ? "행운" : "Lucky")
                        .font(af(d, 28, bold: true)).foregroundStyle(p.ink)
                }

                // count pill
                if total > 0 {
                    HStack(spacing: 4) {
                        CloverSprig(size: 12, tint: .fresh).frame(width: 12, height: 14)
                        Text(verbatim: "×\(total)").font(af(d, 12, bold: true)).foregroundStyle(p.inkSoft)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill((p.dark ? Color.white.opacity(0.10) : Color.white.opacity(0.55))))
                    .frame(width: W, alignment: .trailing)
                }

                // empty state
                if total == 0 {
                    VStack(spacing: 6) {
                        CloverSprig(size: 34, tint: .pale).opacity(0.8)
                        Text(d.lang == "zh" ? "集满四片叶片\n就能长出第一朵四叶草！" : "Collect 4 leaves to\ngrow your first clover!")
                            .font(af(d, 12)).foregroundStyle(p.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: W).position(x: W / 2, y: H * 0.55)
                }
            }
            .frame(width: W, height: H, alignment: .topLeading)
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Widget definitions
// ═══════════════════════════════════════════
struct PaletteBG:View{let palette:String;let darkMode:String;@Environment(\.colorScheme) var cs
    var body:some View{let dk:Bool = darkMode == "dark" ? true : (darkMode == "light" ? false : cs == .dark);P.g(palette,dark:dk).bg}}

struct CloveryQuickWriteWidget:Widget{
    let kind="CloveryQuickWrite"
    var body:some WidgetConfiguration{
        StaticConfiguration(kind:kind,provider:CPr()){e in
            if #available(iOS 17.0,*){W1(d:e.data).containerBackground(for:.widget){PaletteBG(palette:e.data.palette,darkMode:e.data.darkMode)}}
            else{W1(d:e.data).background(PaletteBG(palette:e.data.palette,darkMode:e.data.darkMode))}
        }
        .configurationDisplayName("小幸运 · 记录").description("轻触开始记录今天的小幸运 🍀").supportedFamilies([.systemSmall])
    }
}
struct CloveryLeafWidget:Widget{
    let kind="CloveryLeaf"
    var body:some WidgetConfiguration{
        StaticConfiguration(kind:kind,provider:CPr()){e in
            if #available(iOS 17.0,*){W2(d:e.data).containerBackground(for:.widget){PaletteBG(palette:e.data.palette,darkMode:e.data.darkMode)}}
            else{W2(d:e.data).background(PaletteBG(palette:e.data.palette,darkMode:e.data.darkMode))}
        }
        .configurationDisplayName("小幸运 · 叶片").description("查看四叶草生长进度 🌱").supportedFamilies([.systemSmall])
    }
}
struct CloveryDiaryWidget:Widget{
    let kind="CloveryDiary"
    var body:some WidgetConfiguration{
        StaticConfiguration(kind:kind,provider:CPr()){e in
            if #available(iOS 17.0,*){W3(d:e.data).containerBackground(for:.widget){PaletteBG(palette:e.data.palette,darkMode:e.data.darkMode)}}
            else{W3(d:e.data).background(PaletteBG(palette:e.data.palette,darkMode:e.data.darkMode))}
        }
        .configurationDisplayName("小幸运 · 日记").description("日历和最近的幸运记录 📅").supportedFamilies([.systemMedium])
    }
}
struct CloveryFieldWidget:Widget{
    let kind="CloveryField"
    var body:some WidgetConfiguration{
        StaticConfiguration(kind:kind,provider:CPr()){e in
            if #available(iOS 17.0,*){W4(d:e.data).containerBackground(for:.widget){MeadowBG(palette:e.data.palette,darkMode:e.data.darkMode)}}
            else{W4(d:e.data).background(MeadowBG(palette:e.data.palette,darkMode:e.data.darkMode))}
        }
        .configurationDisplayName("小幸运 · 四叶草田").description("你的四叶草花园 🏡").supportedFamilies([.systemLarge])
    }
}

// ═══════════════════════════════════════════
// MARK: - Lock Screen — clover logo (circular)
// ═══════════════════════════════════════════
struct LockCloverView:View{
    var body:some View{
        // Exact logo silhouette (white, leaf shading kept as alpha) so the lock screen tint matches the app icon.
        if let u=Bundle.main.url(forResource:"lock_clover",withExtension:"png"),let d=try? Data(contentsOf:u),let i=UIImage(data:d){
            Image(uiImage:i).renderingMode(.template).resizable().aspectRatio(contentMode:.fit).padding(5).widgetAccentable()
        }else{
            CloverMark().padding(8).widgetAccentable()
        }
    }
}
struct CloveryLockCloverWidget:Widget{
    let kind="CloveryLockClover"
    var body:some WidgetConfiguration{
        StaticConfiguration(kind:kind,provider:CPr()){_ in
            if #available(iOS 17.0,*){LockCloverView().containerBackground(for:.widget){AccessoryWidgetBackground()}}
            else{LockCloverView().background(AccessoryWidgetBackground())}
        }
        .configurationDisplayName("小幸运 · 四叶草").description("锁屏上的四叶草，轻触打开小幸运 🍀").supportedFamilies([.accessoryCircular])
    }
}
