import Observation
import SwiftUI

enum Route: Hashable {
    case chat(Provider)
}

/// App-wide navigation and API-key state.
@MainActor
@Observable
final class AppStore {
    var path: [Route] = []
    var showSettings = false

    private let secrets: SecretStore
    /// Bumped whenever a key changes so views observing key state re-evaluate.
    private var keyRevision = 0

    init(secrets: SecretStore = KeychainSecretStore()) {
        self.secrets = secrets
    }

    func apiKey(for provider: Provider) -> String? {
        _ = keyRevision
        return secrets.value(for: provider.id)
    }

    func hasKey(for provider: Provider) -> Bool {
        apiKey(for: provider) != nil
    }

    func setKey(_ value: String?, for provider: Provider) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        secrets.set(trimmed, for: provider.id)
        keyRevision += 1
    }

    func open(_ provider: Provider) {
        guard provider.status == .available else { return }
        path.append(.chat(provider))
    }
}
