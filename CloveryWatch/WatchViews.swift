import SwiftUI

// ═══════════════════════════════════════════
// MARK: - Home: quick record + review
// ═══════════════════════════════════════════
/// Root: page 1 = the big clover (tap to record), swipe left → page 2 = diary review.
struct WatchRootView: View {
    @ObservedObject var store: WatchStore
    @Environment(\.colorScheme) var cs

    var body: some View {
        let p = store.theme(cs)
        #if os(watchOS)
        TabView {
            WatchHomeView(store: store)
            NavigationStack { WatchReviewView(store: store) }
        }
        .tabViewStyle(.page)
        .containerBackground(p.bg, for: .tabView)
        #else
        WatchHomeView(store: store)
        #endif
    }
}

// ═══════════════════════════════════════════
// MARK: - Home: just the big clover
// ═══════════════════════════════════════════
struct WatchHomeView: View {
    @ObservedObject var store: WatchStore
    @Environment(\.colorScheme) var cs
    @State private var justSaved = false

    var body: some View {
        let p = store.theme(cs)
        let lang = store.lang
        let now = Date()
        ZStack {
            p.bg.ignoresSafeArea()
            GeometryReader { geo in
                // vertical budget: header ~40, footer ~16, margins; the clover (plus stem = 1.1×) gets the rest
                let side: CGFloat = 18
                let avail = geo.size.height - 40 - 16 - 48
                let S = max(60, min(geo.size.width - 2 * side - 28, avail / 1.1))
                VStack(spacing: 0) {
                    // top: weekday + big date, like the app's home screen
                    VStack(spacing: 1) {
                        Text(WS.weekday(now, lang)).font(store.font(12)).foregroundStyle(p.inkMut)
                        Text(WS.bigDate(now, lang)).font(store.font(22, bold: true)).foregroundStyle(p.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 6)
                    clover(p, size: S)
                        .frame(width: S, height: S * 1.1, alignment: .top)
                    Spacer(minLength: 6)
                    // bottom: streak • entries
                    HStack(spacing: 6) {
                        Text(WS.streakText(store.streak, lang))
                        Circle().fill(p.inkMut).frame(width: 3, height: 3)
                        Text(WS.countText(store.entries.count, lang))
                    }
                    .font(store.font(11)).foregroundStyle(p.inkSoft)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, side)
                .padding(.top, 8)
                .padding(.bottom, 14)
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .overlay { if justSaved { SavedOverlay(store: store).transition(.opacity) } }
        .animation(.easeInOut(duration: 0.2), value: justSaved)
    }

    /// The app's home-screen clover: a soft-shadowed quatrefoil with a short stem. Tap = write today's lucky thing.
    @ViewBuilder
    private func clover(_ p: WP, size S: CGFloat) -> some View {
        let leaf = ZStack {
            // short curved stem peeking out under the lower leaves
            Path { path in
                path.move(to: CGPoint(x: S * 0.5, y: S * 0.9))
                path.addQuadCurve(to: CGPoint(x: S * 0.57, y: S * 1.1), control: CGPoint(x: S * 0.46, y: S * 1.01))
            }
            .stroke(p.accentDark, style: StrokeStyle(lineWidth: max(2.5, S * 0.035), lineCap: .round))
            Quatrefoil().fill(p.accent)
                .shadow(color: p.accent.opacity(0.4), radius: S * 0.06, y: S * 0.02)
            VStack(spacing: S * 0.05) {
                Text(WS.t("tapToRecord", store.lang))
                    .font(store.font(max(13, S * 0.115), bold: true))
                    .multilineTextAlignment(.center)
                    .lineLimit(3).minimumScaleFactor(0.7)
                    .frame(width: S * 0.52)
                // hint that both typing and dictation are available in the input sheet
                HStack(spacing: S * 0.05) {
                    Image(systemName: "keyboard")
                    Image(systemName: "mic.fill")
                }
                .font(.system(size: S * 0.085, weight: .semibold))
                .opacity(0.75)
            }
            .foregroundStyle(p.onAccent)
        }
        .frame(width: S, height: S)
        .contentShape(Rectangle())

        #if os(watchOS)
        // Tapping opens the system text input, which includes the dictation (microphone) button.
        TextFieldLink(prompt: Text(WS.t("prompt", store.lang))) {
            leaf
        } onSubmit: { text in
            if store.addEntry(text) { flashSaved() }
        }
        .buttonStyle(.plain)
        #else
        Button { _ = store.addEntry("preview") } label: { leaf }.buttonStyle(.plain)
        #endif
    }

    private func flashSaved() {
        justSaved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { justSaved = false }
    }
}

struct SavedOverlay: View {
    @ObservedObject var store: WatchStore
    @Environment(\.colorScheme) var cs
    var body: some View {
        let p = store.theme(cs)
        ZStack {
            p.bg.ignoresSafeArea()
            VStack(spacing: 8) {
                CloverSprig(size: 44)
                Text(WS.t("saved", store.lang)).font(store.font(18, bold: true)).foregroundStyle(p.ink)
            }
        }
    }
}

// ═══════════════════════════════════════════
// MARK: - Review: entries grouped by day
// ═══════════════════════════════════════════
private func timeLabel(_ ms: Double?) -> String? {
    guard let ms, ms > 100_000_000_000 else { return nil }
    let f = DateFormatter(); f.dateFormat = "HH:mm"
    return f.string(from: Date(timeIntervalSince1970: ms / 1000))
}

struct WatchReviewView: View {
    @ObservedObject var store: WatchStore
    @Environment(\.colorScheme) var cs

    private var groups: [(date: String, entries: [WEntry])] {
        var order: [String] = []
        var map: [String: [WEntry]] = [:]
        for e in store.entries {
            if map[e.date] == nil { order.append(e.date) }
            map[e.date, default: []].append(e)
        }
        return order.map { (date: $0, entries: map[$0]!) }
    }

    var body: some View {
        let p = store.theme(cs)
        let lang = store.lang
        Group {
            if store.entries.isEmpty {
                VStack(spacing: 8) {
                    CloverSprig(size: 34).opacity(0.9)
                    Text(WS.t("empty", lang)).font(store.font(16, bold: true)).foregroundStyle(p.ink)
                    Text(WS.t("emptyHint", lang)).font(store.font(12)).foregroundStyle(p.inkMut)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(groups, id: \.date) { g in
                            HStack(spacing: 6) {
                                Circle().fill(p.accent).frame(width: 6, height: 6)
                                Text(WS.dateLabel(g.date, lang)).font(store.font(14, bold: true)).foregroundStyle(p.inkSoft)
                                if g.entries.count > 1 {
                                    Text("\(g.entries.count)")
                                        .font(.system(size: 10, weight: .bold)).foregroundStyle(p.accentDark)
                                        .frame(width: 18, height: 18).background(Circle().fill(p.accentSoft))
                                }
                            }
                            .padding(.top, 8).padding(.leading, 10)
                            ForEach(g.entries) { e in
                                NavigationLink {
                                    WatchDetailView(store: store, entry: e)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(e.lucky)
                                            .font(store.font(15)).foregroundStyle(p.ink)
                                            .lineLimit(3).multilineTextAlignment(.leading)
                                        if let t = timeLabel(e.createdAt) {
                                            Text(t).font(.system(size: 10, weight: .medium, design: .rounded))
                                                .foregroundStyle(p.inkMut)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(p.paper))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(p.inkMut.opacity(0.2), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 6).padding(.bottom, 10)
                }
            }
        }
        .background(p.bg.ignoresSafeArea())
        #if os(watchOS)
        .containerBackground(p.bg, for: .navigation)
        #endif
        .navigationTitle(WS.t("review", lang))
    }
}

struct WatchDetailView: View {
    @ObservedObject var store: WatchStore
    let entry: WEntry
    @Environment(\.colorScheme) var cs

    var body: some View {
        let p = store.theme(cs)
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    CloverSprig(size: 16)
                    Text(WS.dateLabel(entry.date, store.lang)).font(store.font(14, bold: true)).foregroundStyle(p.inkSoft)
                    if let t = timeLabel(entry.createdAt) {
                        Text(t).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(p.inkMut)
                    }
                }
                Text(entry.lucky)
                    .font(store.font(18)).foregroundStyle(p.ink)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(p.paper))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(p.inkMut.opacity(0.2), lineWidth: 0.5))
                if let tags = entry.tags, !tags.isEmpty {
                    Text(tags.map { "#\($0)" }.joined(separator: " "))
                        .font(store.font(12)).foregroundStyle(p.accentDark)
                }
            }
            .padding(.horizontal, 6).padding(.bottom, 10)
        }
        .background(p.bg.ignoresSafeArea())
        #if os(watchOS)
        .containerBackground(p.bg, for: .navigation)
        #endif
    }
}
