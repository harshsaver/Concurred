import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            SettingsForm()
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                    }
                }
        }
        .frame(width: 560, height: 540)
    }
}

struct SettingsForm: View {
    @Environment(AppStore.self) private var store
    @State private var drafts: [String: String] = [:]
    @State private var errors: [String: String] = [:]

    var body: some View {
        Form {
            Section {
                Text("API keys are stored in your macOS Keychain. Open a provider or choose Load saved key to use an existing key. Each key is sent only to its provider.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Provider.all) { provider in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("API key", text: Binding(
                            get: { drafts[provider.id] ?? "" }, set: { drafts[provider.id] = $0 }
                        ), prompt: Text(provider.keyPlaceholder))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel("\(provider.name) API key")
                        .onSubmit { save(provider) }
                        if !store.hasLoadedKey(for: provider) || store.keyError(for: provider) != nil {
                            Button(store.keyError(for: provider) == nil ? "Load saved key" : "Retry Keychain access") {
                                store.reloadKey(for: provider)
                                if store.keyError(for: provider) == nil {
                                    drafts[provider.id] = store.apiKey(for: provider) ?? ""
                                    errors[provider.id] = nil
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            Label(status(provider),
                                  systemImage: changed(provider) ? "pencil.circle" : (store.hasKey(for: provider) ? "checkmark.circle" : "key"))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let url = provider.apiKeysURL { Link("Get a key", destination: url).font(.caption) }
                            Button("Save") { save(provider) }
                                .disabled(trimmed(provider).isEmpty || !changed(provider))
                            Button("Clear", role: .destructive) { clear(provider) }
                                .disabled(!store.hasKey(for: provider) && trimmed(provider).isEmpty)
                        }
                        if let error = errors[provider.id] ?? store.keyError(for: provider) {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                } header: { Label(provider.name, systemImage: provider.symbol) }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadDrafts)
    }

    private func trimmed(_ provider: Provider) -> String {
        (drafts[provider.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func changed(_ provider: Provider) -> Bool { trimmed(provider) != (store.apiKey(for: provider) ?? "") }
    private func status(_ provider: Provider) -> String {
        if changed(provider) { return "Unsaved changes" }
        if store.hasKey(for: provider) { return "Saved" }
        if store.keyError(for: provider) != nil { return "Key unavailable" }
        return store.hasLoadedKey(for: provider) ? "No key saved" : "Enter a key or load one"
    }
    private func loadDrafts() {
        for provider in Provider.all { drafts[provider.id] = store.apiKey(for: provider) ?? "" }
    }
    private func save(_ provider: Provider) {
        guard !trimmed(provider).isEmpty else { return }
        do {
            try store.setKey(trimmed(provider), for: provider)
            drafts[provider.id] = store.apiKey(for: provider) ?? ""
            errors[provider.id] = nil
        } catch { errors[provider.id] = error.localizedDescription }
    }
    private func clear(_ provider: Provider) {
        do {
            try store.setKey(nil, for: provider)
            drafts[provider.id] = ""
            errors[provider.id] = nil
        } catch { errors[provider.id] = error.localizedDescription }
    }
}
