import Foundation

struct AccountEntitlementCacheSnapshot: Codable, Equatable, Sendable {
    let accountID: String
    let environment: AccountEntitlementEnvironment
    let entitlements: [AccountEntitlementSummary]
    let fetchedAt: Date
}

@MainActor
protocol AccountEntitlementCaching: AnyObject {
    func save(
        accountID: String,
        environment: AccountEntitlementEnvironment,
        entitlements: [AccountEntitlementSummary],
        fetchedAt: Date
    ) throws
    func load(
        accountID: String,
        environment: AccountEntitlementEnvironment
    ) throws -> AccountEntitlementCacheSnapshot?
    func clear() throws
}

@MainActor
final class AccountEntitlementCache: AccountEntitlementCaching {
    static let maximumAge: TimeInterval = 72 * 60 * 60

    private let fileURL: URL
    private let fileStore: AtomicJSONFileStore
    private let now: () -> Date

    init(
        fileURL: URL = AccountEntitlementCache.defaultFileURL(),
        fileStore: AtomicJSONFileStore = AtomicJSONFileStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL
        self.fileStore = fileStore
        self.now = now
    }

    func save(
        accountID: String,
        environment: AccountEntitlementEnvironment,
        entitlements: [AccountEntitlementSummary],
        fetchedAt: Date
    ) throws {
        let snapshot = AccountEntitlementCacheSnapshot(
            accountID: accountID,
            environment: environment,
            entitlements: entitlements,
            fetchedAt: fetchedAt
        )
        try fileStore.write(
            snapshot,
            to: fileURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication],
            attributes: [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
        )
    }

    func load(
        accountID: String,
        environment: AccountEntitlementEnvironment
    ) throws -> AccountEntitlementCacheSnapshot? {
        guard let snapshot = try fileStore.read(
            AccountEntitlementCacheSnapshot.self,
            from: fileURL
        ), snapshot.accountID == accountID,
           snapshot.environment == environment
        else {
            return nil
        }

        let age = now().timeIntervalSince(snapshot.fetchedAt)
        guard age >= 0, age <= Self.maximumAge else { return nil }
        return snapshot
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    nonisolated private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Clovery", isDirectory: true)
            .appendingPathComponent("account-entitlements.json")
    }
}
