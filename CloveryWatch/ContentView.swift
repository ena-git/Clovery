import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WatchSessionStore
    @State private var draftLucky: String = ""
    @State private var savedBannerVisible: Bool = false

    private var accentColor: Color {
        switch store.palette {
        case "sakura": return Color(red: 0.84, green: 0.48, blue: 0.56)
        case "ocean": return Color(red: 0.30, green: 0.57, blue: 0.71)
        case "kraft": return Color(red: 0.67, green: 0.51, blue: 0.33)
        default: return Color(red: 0.37, green: 0.64, blue: 0.37)
        }
    }

    private var todayISO: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.string(from: Date())
    }

    private var todayEntries: [WatchEntry] {
        store.entries.filter { $0.date == todayISO }
    }

    private var isZH: Bool { store.lang == "zh" }
    private var isJA: Bool { store.lang == "ja" }
    private var isKO: Bool { store.lang == "ko" }

    var body: some View {
        TabView {
            todayPage
            progressPage
            recentPage
        }
        .tabViewStyle(.verticalPage)
        .onAppear {
            store.requestSync()
        }
    }

    private var todayPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "leaf.fill")
                        .foregroundStyle(accentColor)
                    Text(todayTitle)
                        .font(.headline)
                    Spacer()
                    Text("\(todayEntries.count)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.22), in: Capsule())
                }

                if let latest = todayEntries.first {
                    Text(latest.lucky)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Text(emptyTodayPrompt)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }

                TextField(inputPlaceholder, text: $draftLucky)
                    .submitLabel(.done)
                    .onSubmit {
                        commitDraft()
                    }

                Button {
                    commitDraft()
                } label: {
                    Label(saveButtonTitle, systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .disabled(draftLucky.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if savedBannerVisible {
                    Text(savedLabel)
                        .font(.caption2)
                        .foregroundStyle(accentColor)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var progressPage: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(accentColor.opacity(0.22), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(store.leafCount) / 4.0)
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(store.leafCount)/4")
                        .font(.title3.bold().monospacedDigit())
                    Text(leafProgressSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 82, height: 82)

            HStack(spacing: 12) {
                statPill(value: "\(store.streak)", label: streakLabel)
                statPill(value: "\(store.totalClovers)", label: cloversLabel)
                statPill(value: "\(store.totalEntries)", label: entriesLabel)
            }

            Button {
                store.requestSync()
            } label: {
                Label(store.isSyncing ? syncingLabel : syncLabel, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 4)
    }

    private var recentPage: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(accentColor)
                        Text(noEntriesLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List(store.entries.prefix(15)) { entry in
                        NavigationLink {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(entry.date)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(accentColor)
                                    Text(entry.lucky)
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding()
                            }
                            .navigationTitle(todayTitle)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.date)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(accentColor)
                                Text(entry.lucky)
                                    .font(.footnote)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private func statPill(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.footnote.bold().monospacedDigit())
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func commitDraft() {
        let trimmed = draftLucky.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.submitNewLucky(trimmed)
        draftLucky = ""
        savedBannerVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            savedBannerVisible = false
        }
    }

    private var todayTitle: String {
        isZH ? "今日幸运" : isJA ? "今日の幸運" : isKO ? "오늘의 행운" : "Today's Luck"
    }

    private var emptyTodayPrompt: String {
        isZH ? "记下今天一件开心小事" : isJA ? "今日の小さな幸せを記録" : isKO ? "오늘의 작은 행운을 기록해요" : "Note a small lucky moment"
    }

    private var inputPlaceholder: String {
        isZH ? "写一件小幸运..." : isJA ? "小さな幸運を入力..." : isKO ? "작은 행운 적기..." : "Add a lucky note..."
    }

    private var saveButtonTitle: String {
        isZH ? "保存" : isJA ? "保存" : isKO ? "저장" : "Save"
    }

    private var savedLabel: String {
        isZH ? "已记下，将同步到 iPhone" : isJA ? "記録済み（iPhoneへ同期）" : isKO ? "저장됨 (iPhone과 동기화)" : "Saved · Syncing to iPhone"
    }

    private var leafProgressSubtitle: String {
        isZH ? "生长中" : isJA ? "育成中" : isKO ? "성장 중" : "Leaves"
    }

    private var streakLabel: String {
        isZH ? "连续" : isJA ? "連続" : isKO ? "연속" : "Streak"
    }

    private var cloversLabel: String {
        isZH ? "四叶草" : isJA ? "四つ葉" : isKO ? "네잎" : "Clovers"
    }

    private var entriesLabel: String {
        isZH ? "总计" : isJA ? "合計" : isKO ? "전체" : "Total"
    }

    private var syncLabel: String {
        isZH ? "同步" : isJA ? "同期" : isKO ? "동기화" : "Sync"
    }

    private var syncingLabel: String {
        isZH ? "同步中..." : isJA ? "同期中..." : isKO ? "동기화 중..." : "Syncing..."
    }

    private var noEntriesLabel: String {
        isZH ? "在手表记下一件小幸运，或打开 iPhone 同步" : isJA ? "Watchで記録するか、iPhoneを開いて同期してください" : isKO ? "Watch에서 기록하거나 iPhone 앱을 열어 동기화하세요" : "Add a note here or open Clovery on iPhone to sync"
    }
}
