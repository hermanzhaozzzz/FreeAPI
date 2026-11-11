import Foundation
import Security

enum KeychainStore {
    private static let service = "local.freeapi.apikey"

    private static func baseQuery(account: String, synchronizable: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if synchronizable {
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        return query
    }

    static func read(account: String) -> String? {
        if let value = read(account: account, synchronizable: true) {
            return value
        }
        guard let value = read(account: account, synchronizable: false) else {
            return nil
        }
        // Older builds stored a local-only item. Keep it, but try to add a
        // synchronizable copy so iCloud Keychain users get it on other Macs.
        _ = write(value, account: account, synchronizable: true)
        return value
    }

    private static func read(account: String, synchronizable: Bool) -> String? {
        var query = baseQuery(account: account, synchronizable: synchronizable)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        if value.isEmpty {
            delete(account: account)
            return true
        }
        if write(value, account: account, synchronizable: true) {
            return true
        }
        return write(value, account: account, synchronizable: false)
    }

    private static func write(_ value: String, account: String, synchronizable: Bool) -> Bool {
        let data = Data(value.utf8)
        var attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: synchronizable
                ? kSecAttrAccessibleWhenUnlocked
                : kSecAttrAccessibleAfterFirstUnlock
        ]
        if synchronizable {
            attributes[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }

        let query = baseQuery(account: account, synchronizable: synchronizable)
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var addQuery = query
        for (key, item) in attributes { addQuery[key] = item }
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account, synchronizable: true) as CFDictionary)
        SecItemDelete(baseQuery(account: account, synchronizable: false) as CFDictionary)
    }
}
