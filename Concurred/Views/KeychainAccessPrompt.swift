import AppKit

/// Explains macOS authentication before a UI action touches Keychain.
/// The app never asks for, receives, or overrides the user's Mac password.
@MainActor
enum KeychainAccessPrompt {
    @discardableResult
    static func authorize(in store: AppStore, explainAgain: Bool = false) -> Bool {
        guard store.keyStorage == .keychain,
              explainAgain || store.needsKeychainExplanation else { return true }

        let alert = NSAlert()
        alert.messageText = "Why macOS may ask for your password"
        alert.informativeText = "Your provider API keys are saved in macOS Keychain. macOS may ask for your login password before letting Concurred use a key. Concurred never sees your Mac password.\n\nIf macOS offers Always Allow, choose it to remember access to that provider's key. Allow only grants access this time.\n\nPrefer no Keychain prompts? Use local storage. Keys will be saved in an unencrypted file on this Mac. Enter your API keys again in Settings; existing Keychain keys stay where they are."
        alert.addButton(withTitle: "Use Keychain")
        alert.addButton(withTitle: "Use Local Storage")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            store.acknowledgeKeychainExplanation()
            return true
        case .alertSecondButtonReturn:
            store.changeKeyStorage(to: .local)
            return true
        default:
            return false
        }
    }

    static func loadKey(for provider: Provider, in store: AppStore, retry: Bool = false) {
        guard retry || !store.hasLoadedKey(for: provider) else { return }
        guard authorize(in: store) else {
            store.cancelKeyLoading(for: provider)
            return
        }
        store.reloadKey(for: provider)
    }

    static func changeStorage(to mode: KeyStorageMode, in store: AppStore) {
        guard mode != store.keyStorage else { return }
        if mode == .local {
            let alert = NSAlert()
            alert.messageText = "Store API keys without Keychain prompts?"
            alert.informativeText = "Keys you save will be stored in an unencrypted file on this Mac, accessible to your macOS account.\n\nEnter your keys again after switching. Existing Keychain keys stay in Keychain and are not copied or deleted. You can switch back in Settings."
            alert.addButton(withTitle: "Use Local Storage")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        store.changeKeyStorage(to: mode)
    }
}
