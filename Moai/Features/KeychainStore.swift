import Foundation
import Security

/// Minimal Keychain wrapper for the one secret Moai keeps.
enum KeychainStore {
    private static let service = "com.cj.moai"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if value.isEmpty {
            let status = SecItemDelete(base as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            status = SecItemAdd(add as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    /// One-time move of a legacy UserDefaults secret into the Keychain.
    /// The defaults copy is only removed once the Keychain verifiably
    /// holds the value — a failed write must never destroy the last copy.
    static func migrateFromDefaults(key: String, account: String) {
        guard let legacy = UserDefaults.standard.string(forKey: key),
              !legacy.isEmpty
        else { return }
        if read(account) == nil {
            guard write(legacy, account: account) else { return }
        }
        guard read(account) != nil else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }
}
