import Foundation
import Security

/// Persists per-provider API keys.
protocol SecretStore: Sendable {
    func value(for key: String) -> String?
    func set(_ value: String?, for key: String)
}

/// Stores secrets as generic-password items in the macOS Keychain.
struct KeychainSecretStore: SecretStore {
    let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "dev.october.concord") {
        self.service = service
    }

    func value(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8),
              !string.isEmpty
        else { return nil }
        return string
    }

    func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        // Simplest correct approach: delete any existing item, then add fresh.
        SecItemDelete(base as CFDictionary)

        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
