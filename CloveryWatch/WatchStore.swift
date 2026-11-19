import SwiftUI
import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
#if os(watchOS)
import WatchKit
#endif

struct WEntry: Codable, Identifiable, Equatable {
    var id: String
    var date: String          // yyyy-MM-dd
    var lucky: String
    var mood: String?
    var createdAt: Double?
    var tags: [String]?
}

/// Holds the diary snapshot pushed from the iPhone plus entries written on the watch that the phone
/// has not echoed back yet. The iPhone app stays the source of truth.
final class WatchStore: NSObject, ObservableObject {
    @Published private(set) var phoneEntries: [WEntry] = []
    @Published private(set) var localEntries: [WEntry] = []
    @Published var fontName = "Gaegu"
    @Published var palette = "clover"
    @Published var lang = "zh"
    @Published var darkMode = "auto"
    @Published var name = ""

    private let defaults = UserDefaults.standard

    override init() {
        super.init()
        load()
        #if canImport(WatchConnectivity)
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        #endif
    }

    // ── derived ──
    /// Phone entries plus watch-only ones, newest first.
    var entries: [WEntry] {
        let known = Set(phoneEntries.map { $0.id })
        let merged = phoneEntries + localEntries.filter { !known.contains($0.id) }
        return merged.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return ($0.createdAt ?? 0) > ($1.createdAt ?? 0)
        }
    }
    var todayEntries: [WEntry] { entries.filter { $0.date == Self.todayString() } }
    var uniqueDays: Set<String> { Set(entries.map { $0.date }) }
    var streak: Int {
        let days = uniqueDays
        let cal = Calendar.current
        var cursor = Date()
        if !days.contains(Self.dayString(cursor)) { cursor = cal.date(byAdding: .day, value: -1, to: cursor)! }
        var n = 0
        while days.contains(Self.dayString(cursor)) {
            n += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return n
    }

    func isDark(_ cs: ColorScheme) -> Bool {
        switch darkMode {
        case "dark": return true
        case "light": return false
        default: return cs == .dark      // the watch is always dark, so "follow system" resolves to dark
        }
    }
    func theme(_ cs: ColorScheme) -> WP { WP.g(palette, dark: isDark(cs)) }
    func font(_ size: CGFloat, bold: Bool = false) -> Font { WFont.make(fontName, lang, size, bold: bold) }

    static func dayString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
        return f.string(from: d)
    }
    static func todayString() -> String { dayString(Date()) }

    // ── writing ──
    /// Saves a new entry locally (so it shows up immediately) and queues it for the iPhone.
    @discardableResult
    func addEntry(_ rawText: String) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let entry = WEntry(id: UUID().uuidString.lowercased(), date: Self.todayString(), lucky: text, mood: "lucky",
                           createdAt: (Date().timeIntervalSince1970 * 1000).rounded(), tags: [])
        localEntries.append(entry)
        persistLocal()
        #if canImport(WatchConnectivity)
        if WCSession.isSupported() {
            var info: [String: Any] = [
                "type": "newEntry", "id": entry.id, "date": entry.date, "lucky": entry.lucky,
                "mood": "lucky", "createdAt": entry.createdAt ?? 0,
            ]
            info["source"] = "watch"
            WCSession.default.transferUserInfo(info)
        }
        #endif
        #if os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
        return true
    }

    // ── persistence ──
    private func load() {
        let dec = JSONDecoder()
        if let d = defaults.data(forKey: "w_phone_entries"), let v = try? dec.decode([WEntry].self, from: d) { phoneEntries = v }
        if let d = defaults.data(forKey: "w_local_entries"), let v = try? dec.decode([WEntry].self, from: d) { localEntries = v }
        fontName = defaults.string(forKey: "w_font") ?? fontName
        palette = defaults.string(forKey: "w_palette") ?? palette
        lang = defaults.string(forKey: "w_lang") ?? lang
        darkMode = defaults.string(forKey: "w_dark") ?? darkMode
        name = defaults.string(forKey: "w_name") ?? name
    }
    private func persistLocal() {
        if let d = try? JSONEncoder().encode(localEntries) { defaults.set(d, forKey: "w_local_entries") }
    }

    /// Applies a context dictionary sent by the iPhone app.
    func apply(context: [String: Any]) {
        if let json = context["entries"] as? String, let data = json.data(using: .utf8),
           let list = try? JSONDecoder().decode([WEntry].self, from: data) {
            phoneEntries = list
            defaults.set(data, forKey: "w_phone_entries")
            // Anything the phone has echoed back no longer needs to be kept locally.
            let known = Set(list.map { $0.id })
            let remaining = localEntries.filter { !known.contains($0.id) }
            if remaining.count != localEntries.count { localEntries = remaining; persistLocal() }
        }
        if let v = context["font"] as? String { fontName = v; defaults.set(v, forKey: "w_font") }
        if let v = context["palette"] as? String { palette = v; defaults.set(v, forKey: "w_palette") }
        if let v = context["lang"] as? String { lang = v; defaults.set(v, forKey: "w_lang") }
        if let v = context["dark"] as? String { darkMode = v; defaults.set(v, forKey: "w_dark") }
        if let v = context["name"] as? String { name = v; defaults.set(v, forKey: "w_name") }
    }
}

#if canImport(WatchConnectivity)
extension WatchStore: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        guard !ctx.isEmpty else { return }
        DispatchQueue.main.async { self.apply(context: ctx) }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.apply(context: applicationContext) }
    }
}
#endif

// ═══════════════════════════════════════════
// MARK: - Strings
// ═══════════════════════════════════════════
enum WS {
    static func t(_ key: String, _ lang: String) -> String {
        let table: [String: [String: String]] = [
            "record":   ["zh": "记录", "zh-TW": "記錄", "ja": "記録", "ko": "기록", "en": "Write"],
            "review":   ["zh": "回顾", "zh-TW": "回顧", "ja": "振り返り", "ko": "돌아보기", "en": "Review"],
            "prompt":   ["zh": "今天最幸运的小事是什么？", "zh-TW": "今天最幸運的小事是什麼？", "ja": "今日のラッキーは？", "ko": "오늘의 행운은?", "en": "What's your lucky moment?"],
            "saved":    ["zh": "已记录", "zh-TW": "已記錄", "ja": "記録しました", "ko": "기록했어요", "en": "Saved"],
            "today":    ["zh": "今天", "zh-TW": "今天", "ja": "今日", "ko": "오늘", "en": "Today"],
            "yesterday":["zh": "昨天", "zh-TW": "昨天", "ja": "昨日", "ko": "어제", "en": "Yesterday"],
            "empty":    ["zh": "还没有记录", "zh-TW": "還沒有記錄", "ja": "まだ記録がありません", "ko": "아직 기록이 없어요", "en": "No entries yet"],
            "emptyHint":["zh": "写下第一条小幸运，或在 iPhone 上打开小幸运同步", "zh-TW": "寫下第一則小幸運，或在 iPhone 上開啟小幸運同步",
                         "ja": "最初のラッキーを書くか、iPhoneでアプリを開いて同期", "ko": "첫 행운을 적거나 iPhone에서 앱을 열어 동기화하세요",
                         "en": "Write your first one, or open Clovery on iPhone to sync"],
            "tapToRecord": ["zh": "点击记录\n今日幸运", "zh-TW": "點擊記錄\n今日幸運", "ja": "タップして\n今日のラッキーを記録", "ko": "탭하여\n오늘의 행운 기록", "en": "Tap to record\ntoday's luck"],
            "tapToWrite": ["zh": "点按后可语音输入", "zh-TW": "點按後可語音輸入", "ja": "タップして音声入力", "ko": "탭하여 음성 입력", "en": "Tap to dictate"],
            "todayDone":["zh": "今天已记录 %d 条", "zh-TW": "今天已記錄 %d 則", "ja": "今日は%d件記録", "ko": "오늘 %d개 기록", "en": "%d logged today"],
        ]
        let l = table[key]?[lang] != nil ? lang : (lang == "zh-TW" ? "zh" : "en")
        return table[key]?[l] ?? table[key]?["en"] ?? key
    }


    // ── home header / footer (mirrors the app's home screen) ──
    static func weekday(_ d: Date, _ lang: String) -> String {
        let i = Calendar.current.component(.weekday, from: d) - 1   // 0 = Sunday
        switch lang {
        case "zh": return ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][i]
        case "zh-TW": return ["週日", "週一", "週二", "週三", "週四", "週五", "週六"][i]
        case "ja": return ["日", "月", "火", "水", "木", "金", "土"][i] + "曜日"
        case "ko": return ["일", "월", "화", "수", "목", "금", "토"][i] + "요일"
        default: return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][i]
        }
    }
    static func bigDate(_ d: Date, _ lang: String) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: d)
        let m = c.month ?? 1, day = c.day ?? 1
        switch lang {
        case "zh", "zh-TW", "ja": return "\(m)月\(day)日"
        case "ko": return "\(m)월 \(day)일"
        default:
            let n = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][max(0, min(11, m - 1))]
            return "\(n) \(day)"
        }
    }
    static func streakText(_ n: Int, _ lang: String) -> String {
        switch lang {
        case "zh": return "连续 \(n) 天"
        case "zh-TW": return "連續 \(n) 天"
        case "ja": return "連続\(n)日"
        case "ko": return "연속 \(n)일"
        default: return "\(n)-day streak"
        }
    }
    static func countText(_ n: Int, _ lang: String) -> String {
        switch lang {
        case "zh": return "\(n) 条记录"
        case "zh-TW": return "\(n) 則記錄"
        case "ja": return "\(n)件の記録"
        case "ko": return "기록 \(n)개"
        default: return n == 1 ? "1 entry" : "\(n) entries"
        }
    }

    static func streakLine(_ streak: Int, _ count: Int, _ lang: String) -> String {
        switch lang {
        case "zh", "zh-TW": return "连续 \(streak) 天 · \(count) 条"
        case "ja": return "連続\(streak)日 · \(count)件"
        case "ko": return "연속 \(streak)일 · \(count)개"
        default: return "\(streak) days · \(count) entries"
        }
    }

    static func dateLabel(_ iso: String, _ lang: String) -> String {
        if iso == WatchStore.todayString() { return t("today", lang) }
        let cal = Calendar.current
        if let y = cal.date(byAdding: .day, value: -1, to: Date()), iso == WatchStore.dayString(y) { return t("yesterday", lang) }
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count >= 3 else { return iso }
        switch lang {
        case "zh", "zh-TW", "ja": return "\(p[1])月\(p[2])日"
        case "ko": return "\(p[1])월 \(p[2])일"
        default:
            let m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][max(0, min(11, p[1] - 1))]
            return "\(m) \(p[2])"
        }
    }
}
