// SPDX-License-Identifier: Apache-2.0
import ATCCore
import Foundation
import Security

/// `SecretStore` on the login Keychain (ATC-246, design 11.5): generic password items, this device only,
/// not synchronised, readable only while unlocked. The only place a token rests. Errors carry a status code, never a value.
final class KeychainStore: SecretStore {
    private func query(_ key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.serviceName,
            kSecAttrAccount as String: key.account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    func read(_ key: SecretKey) throws -> String? {
        var q = query(key)
        q[kSecReturnData as String] = kCFBooleanTrue
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStoreError.failed(Int(status)) }
        guard let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String, for key: SecretKey) throws {
        let data = Data(value.utf8)
        let update = SecItemUpdate(query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw SecretStoreError.failed(Int(update)) }
        var add = query(key)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.failed(Int(status)) }
    }

    func delete(_ key: SecretKey) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.failed(Int(status)) }
    }

    /// Looks for the item without asking for its data, so a rebuilt app does not trigger the Keychain prompt just to draw Settings.
    func exists(_ key: SecretKey) -> Bool {
        var q = query(key)
        q[kSecReturnAttributes as String] = kCFBooleanTrue
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }
}
