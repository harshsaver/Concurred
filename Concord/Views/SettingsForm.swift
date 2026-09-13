import SwiftUI

/// Sheet wrapper presented from the home screen's gear button.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsForm()
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .frame(width: 540, height: 480)
    }
}

/// The API-key editor, reused by both the sheet and the macOS Settings scene (⌘,).
struct SettingsForm: View {
    @Environment(AppStore.self) private var store
    @State private var drafts: [String: String] = [:]

    var body: some View {
        Form {
            Section {
                Text("API keys are stored in your macOS Keychain and are only ever sent to the provider you select.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(Provider.all) { provider in
                Section {
                    keyRow(for: provider)
                } header: {
                    HStack(spacing: 8) {
                        Label(provider.name, systemImage: provider.symbol)
                        if provider.status == .closed {
                            Text("CLOSED")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadDrafts)
    }

    private func keyRow(for provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(provider.keyPlaceholder, text: binding(for: provider))
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                if store.hasKey(for: provider) {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                if let url = provider.apiKeysURL {
                    Link("Get a key", destination: url).font(.caption)
                }
                Button("Save") { save(provider) }
                    .disabled(draft(provider).isEmpty || draft(provider) == store.apiKey(for: provider))
                Button("Clear") { clear(provider) }
                    .disabled(!store.hasKey(for: provider))
            }
        }
        .padding(.vertical, 4)
    }

    private func draft(_ provider: Provider) -> String {
        drafts[provider.id] ?? ""
    }

    private func binding(for provider: Provider) -> Binding<String> {
        Binding(
            get: { drafts[provider.id] ?? "" },
            set: { drafts[provider.id] = $0 }
        )
    }

    private func loadDrafts() {
        for provider in Provider.all {
            drafts[provider.id] = store.apiKey(for: provider) ?? ""
        }
    }

    private func save(_ provider: Provider) {
        store.setKey(draft(provider), for: provider)
    }

    private func clear(_ provider: Provider) {
        drafts[provider.id] = ""
        store.setKey(nil, for: provider)
    }
}
