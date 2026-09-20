import Foundation
import Security

/// Persists per-provider API keys.
protocol SecretStore: Sendable {
    func value(for key: String) throws -> String?
    func set(_ value: String?, for key: String) throws
}

/// Stores secrets as generic-password items in the macOS Keychain.
struct KeychainSecretStore: SecretStore {
    let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "dev.october.concord") {
        self.service = service
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? "Operation failed (\(status)).")"
        }
    }

    func value(for key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        return string.isEmpty ? nil : string
    }

    func set(_ value: String?, for key: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(base as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError(status: status)
            }
            return
        }
        let data = Data(value.utf8)
        // Updating in place preserves the old secret if Keychain rejects the write.
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let added = SecItemAdd(attributes as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }
}
