import SwiftUI

@MainActor
struct DiaryTrashView: View {
    @Environment(\.dismiss) private var dismiss
    let trashStore: DiaryTrashStore
    let onRestore: ([String: JSONValue]) -> Void

    @State private var items: [DiaryTrashItem] = []
    @State private var showsClearConfirmation = false
    @State private var selectedItem: DiaryTrashItem?
    @State private var showsItemAction = false

    private let highlightGreen = Color(red: 122 / 255.0, green: 179 / 255.0, blue: 117 / 255.0)
    private let borderColor = Color(red: 0xd6 / 255.0, green: 0xd6 / 255.0, blue: 0xd6 / 255.0)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.authBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Fixed nav row
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "arrow.backward")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.authInk)
                                .padding(12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        if !items.isEmpty {
                            Text("清空")
                                .cloveryFont(.caption)
                                .foregroundColor(.red)
                                .padding(.trailing, 20)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                                .onTapGesture { showsClearConfirmation = true }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel("清空回收站")
                        }
                    }
                    .padding(.horizontal, 8)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            titleView
                                .padding(.leading, 20)
                                .padding(.top, 4)
                                .padding(.bottom, 20)

                            if items.isEmpty {
                                emptyView
                            } else {
                                contentCard
                                    .padding(.horizontal, 16)
                                footerNote
                            }
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { items = trashStore.load() }
        .confirmationDialog(
            "确定清空回收站？此操作不可撤销。",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空回收站", role: .destructive) {
                trashStore.deleteAll()
                items = []
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("", isPresented: $showsItemAction, titleVisibility: .hidden) {
            Button("恢复日记") {
                if let item = selectedItem,
                   let entry = trashStore.restore(entryID: item.entryID ?? "")
                {
                    onRestore(entry)
                    dismiss()
                }
            }
            Button("永久删除", role: .destructive) {
                if let item = selectedItem {
                    trashStore.delete(entryID: item.entryID ?? "")
                    withAnimation { items = trashStore.load() }
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Title with green highlight bar

    private var titleView: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(highlightGreen)
                .frame(width: 220, height: 20)
                .rotationEffect(.degrees(-8.3))
                .offset(x: 2, y: 4)

            Text("日记回收站")
                .cloveryFont(.heading)
                .foregroundColor(.authInk)
                .rotationEffect(.degrees(-7.74))
        }
        .frame(height: 62, alignment: .bottomLeading)
    }

    // MARK: - Content card (green background with white rows)

    private var contentCard: some View {
        VStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element.entryID) { _, item in
                trashRow(item: item)
            }
        }
        .padding(16)
        .background(Color.authPanel, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func trashRow(item: DiaryTrashItem) -> some View {
        HStack {
            Text(item.rowText)
                .cloveryFont(.caption)
                .foregroundColor(.authInk)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .light))
                .foregroundColor(borderColor)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedItem = item
            showsItemAction = true
        }
    }

    // MARK: - Empty state

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.authPlaceholder)
            Text("回收站为空")
                .cloveryFont(.action)
                .foregroundColor(.authPlaceholder)
            Text("删除的日记将在这里保留 30 天")
                .cloveryFont(.caption)
                .foregroundColor(.authPlaceholder)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 80)
    }

    private var footerNote: some View {
        Text("删除超过 30 天的日记将被永久移除")
            .cloveryFont(.footnote)
            .foregroundColor(.authPlaceholder)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
}

// MARK: - DiaryTrashItem helpers

private extension DiaryTrashItem {
    var entryID: String? { entry.stringValue(for: "id") }

    var previewText: String {
        entry.stringValue(for: "lucky") ?? entry.stringValue(for: "text") ?? "（无内容）"
    }

    var dateShort: String {
        guard let d = entry.stringValue(for: "date"), d.count >= 10 else { return "" }
        let s = String(d.prefix(10))
        let parts = s.split(separator: "-")
        guard parts.count == 3,
              let m = Int(parts[1]), let day = Int(parts[2]) else { return s }
        return "\(parts[0]).\(m).\(day)"
    }

    var rowText: String {
        let text = previewText
        let date = dateShort
        return date.isEmpty ? text : "\(text) - \(date)"
    }
}
