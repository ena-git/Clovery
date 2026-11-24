import Foundation
import Security

protocol KeychainTrialBacking {
    func readData(service: String, account: String) -> Data?
    func writeData(_ data: Data, service: String, account: String) -> Bool
}

struct LiveKeychainTrialBacking: KeychainTrialBacking {
    func readData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return data
    }

    func writeData(_ data: Data, service: String, account: String) -> Bool {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }
}

/// Persists the board free-trial usage count in iOS Keychain so deleting and
/// reinstalling the app cannot reset the trial allowance.
final class KeychainTrialStore {
    static let shared = KeychainTrialStore()
    static let maxTrials = 3

    private let service: String
    private let account: String
    private let backing: KeychainTrialBacking
    private let fallbackDefaults: UserDefaults
    private let fallbackKey = "clovery_board_trial_count_fallback"

    init(
        service: String = "com.clovery.app.board",
        account: String = "board_trial_count",
        backing: KeychainTrialBacking = LiveKeychainTrialBacking(),
        fallbackDefaults: UserDefaults = .standard
    ) {
        self.service = service
        self.account = account
        self.backing = backing
        self.fallbackDefaults = fallbackDefaults
    }

    func currentCount() -> Int {
        if let data = backing.readData(service: service, account: account),
           let str = String(data: data, encoding: .utf8),
           let parsed = Int(str) {
            return clamp(parsed)
        }
        return clamp(fallbackDefaults.integer(forKey: fallbackKey))
    }

    @discardableResult
    func sync(localCount: Int) -> Int {
        let merged = clamp(max(currentCount(), localCount))
        persist(merged)
        return merged
    }

    @discardableResult
    func increment(localCount: Int = 0) -> Int {
        let next = clamp(max(currentCount(), localCount) + 1)
        persist(next)
        return next
    }

    private func persist(_ value: Int) {
        let clamped = clamp(value)
        fallbackDefaults.set(clamped, forKey: fallbackKey)
        if let data = String(clamped).data(using: .utf8) {
            _ = backing.writeData(data, service: service, account: account)
        }
    }

    private func clamp(_ value: Int) -> Int {
        min(max(0, value), Self.maxTrials)
    }
}
