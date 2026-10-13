import Foundation
import Security

/// Stores remote-connection passwords/passphrases in the macOS Keychain —
/// never in `UserDefaults` or anywhere else on disk. Only the secret lives
/// here; everything else about a connection is in `RemoteConnection`
/// (persisted separately via `ConnectionsStore`).
enum KeychainCredentialStore {
    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "код \(status)"
                return "Ошибка Keychain: \(message)"
            }
        }
    }

    private static let service = "ExplorerMacOS.RemoteConnection"

    /// Saves (or updates) the secret for a connection, keyed by its `id`.
    static func savePassword(_ password: String, for connectionID: UUID) throws {
        let account = connectionID.uuidString
        let passwordData = Data(password.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Try an update first; if nothing exists yet, add a new item.
        let attributesToUpdate: [String: Any] = [kSecValueData as String: passwordData]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = passwordData
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    /// Reads the stored secret for a connection, `nil` if none is saved.
    static func password(for connectionID: UUID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the stored secret for a connection (e.g. when the connection
    /// itself is deleted).
    static func deletePassword(for connectionID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID.uuidString,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
