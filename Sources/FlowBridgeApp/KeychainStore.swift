import FlowBridgeShared
import Foundation
import Security

/// Minimal Keychain wrapper for the cloud provider API key. Secrets never
/// touch UserDefaults (shared, unencrypted); the item is device-only and
/// available after first unlock so a background dictation can read it.
enum KeychainStore {
    static func saveCloudAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteCloudAPIKey()
            return
        }
        let data = Data(trimmed.utf8)

        var query = baseQuery()
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadCloudAPIKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteCloudAPIKey() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: FlowBridgeConstants.cloudKeychainService,
            kSecAttrAccount as String: FlowBridgeConstants.cloudKeychainAccount
        ]
    }
}
