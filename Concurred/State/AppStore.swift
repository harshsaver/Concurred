import Observation
import SwiftUI

enum Route: Hashable {
    case chat(Provider)
}

@MainActor
@Observable
final class AppStore {
    var path: [Route] = []
    var showSettings = false
    private let secrets: SecretStore
    private let localSecrets: SecretStore
    private let defaults: UserDefaults
    private(set) var keyStorage: KeyStorageMode
    private(set) var hasExplainedKeychain: Bool
    private var keys: [String: String] = [:]
    private var loadedProviders: Set<String> = []
    private var keyErrors: [String: String] = [:]

    init(secrets: SecretStore = KeychainSecretStore(),
         localSecrets: SecretStore = LocalSecretStore(), defaults: UserDefaults = .standard) {
        self.secrets = secrets
        self.localSecrets = localSecrets
        self.defaults = defaults
        keyStorage = KeyStorageMode(rawValue: defaults.string(forKey: "keyStorage") ?? "") ?? .keychain
        hasExplainedKeychain = defaults.bool(forKey: "hasExplainedKeychain")
    }

    var needsKeychainExplanation: Bool { keyStorage == .keychain && !hasExplainedKeychain }
    private var activeSecrets: SecretStore { keyStorage == .keychain ? secrets : localSecrets }

    func acknowledgeKeychainExplanation() {
        hasExplainedKeychain = true
        defaults.set(true, forKey: "hasExplainedKeychain")
    }

    /// Stores are independent. Switching never unlocks, copies, or deletes keys.
    func changeKeyStorage(to mode: KeyStorageMode) {
        guard mode != keyStorage else { return }
        keyStorage = mode
        defaults.set(mode.rawValue, forKey: "keyStorage")
        keys.removeAll()
        loadedProviders.removeAll()
        keyErrors.removeAll()
    }

    func cancelKeyLoading(for provider: Provider) {
        loadedProviders.insert(provider.id)
        keyErrors[provider.id] = "Key access was cancelled. Retry when you're ready, or choose local storage in Settings."
    }

    func loadKeyIfNeeded(for provider: Provider) {
        guard !hasLoadedKey(for: provider) else { return }
        reloadKey(for: provider)
    }

    func reloadKey(for provider: Provider) {
        // Loading one provider is a user action. Never read every secret at launch,
        // and never retry a denied Keychain request until the user asks.
        loadedProviders.insert(provider.id)
        do {
            keys[provider.id] = try activeSecrets.value(for: provider.id)
            keyErrors[provider.id] = nil
        } catch {
            keyErrors[provider.id] = error.localizedDescription
        }
    }

    func apiKey(for provider: Provider) -> String? { keys[provider.id] }
    func hasKey(for provider: Provider) -> Bool { keys[provider.id] != nil }
    func hasLoadedKey(for provider: Provider) -> Bool { loadedProviders.contains(provider.id) }
    func keyError(for provider: Provider) -> String? { keyErrors[provider.id] }

    func setKey(_ value: String?, for provider: Provider) throws {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed?.isEmpty == false ? trimmed : nil
        try activeSecrets.set(key, for: provider.id)
        keys[provider.id] = key
        loadedProviders.insert(provider.id)
        keyErrors[provider.id] = nil
    }

    func open(_ provider: Provider) {
        path.append(.chat(provider))
    }
}
