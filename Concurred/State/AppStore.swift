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
    private var keys: [String: String] = [:]
    private var loadedProviders: Set<String> = []
    private var keyErrors: [String: String] = [:]

    init(secrets: SecretStore = KeychainSecretStore()) {
        self.secrets = secrets
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
            keys[provider.id] = try secrets.value(for: provider.id)
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
        try secrets.set(key, for: provider.id)
        keys[provider.id] = key
        loadedProviders.insert(provider.id)
        keyErrors[provider.id] = nil
    }

    func open(_ provider: Provider) {
        path.append(.chat(provider))
    }
}
