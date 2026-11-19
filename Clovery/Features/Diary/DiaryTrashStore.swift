import Foundation

struct DiaryTrashItem: Codable {
    let entry: [String: JSONValue]
    let trashedAt: Date

    enum CodingKeys: String, CodingKey {
        case entry
        case trashedAt = "trashed_at"
    }
}

final class DiaryTrashStore {
    static let retentionDays = 30

    private let fileURL: URL
    private let now: () -> Date

    init(accountDirectory: URL, now: @escaping () -> Date = Date.init) {
        self.fileURL = accountDirectory.appendingPathComponent("clovery_trash.json")
        self.now = now
    }

    func load() -> [DiaryTrashItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let items = try? decoder.decode([DiaryTrashItem].self, from: data) else { return [] }
        let cutoff = cutoffDate()
        return items.filter { $0.trashedAt >= cutoff }
    }

    func add(_ entry: [String: JSONValue]) {
        var items = load()
        if let id = entry.stringValue(for: "id") {
            items.removeAll { $0.entry.stringValue(for: "id") == id }
        }
        items.append(DiaryTrashItem(entry: entry, trashedAt: now()))
        save(items)
    }

    func restore(entryID: String) -> [String: JSONValue]? {
        var items = load()
        guard let i = items.firstIndex(where: { $0.entry.stringValue(for: "id") == entryID }) else { return nil }
        let entry = items[i].entry
        items.remove(at: i)
        save(items)
        return entry
    }

    func delete(entryID: String) {
        var items = load()
        items.removeAll { $0.entry.stringValue(for: "id") == entryID }
        save(items)
    }

    func deleteAll() {
        save([])
    }

    func daysRemaining(for item: DiaryTrashItem) -> Int {
        let exp = Calendar.current.date(
            byAdding: .day,
            value: Self.retentionDays,
            to: item.trashedAt
        ) ?? item.trashedAt
        return max(0, Calendar.current.dateComponents([.day], from: now(), to: exp).day ?? 0)
    }

    private func cutoffDate() -> Date {
        Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: now()) ?? now()
    }

    private func save(_ items: [DiaryTrashItem]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}
