import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case let .chat(provider):
                        ProviderWorkspace(provider: provider)
                    }
                }
        }
        .sheet(isPresented: $store.showSettings) {
            SettingsSheet()
        }
    }
}

struct HomeView: View {
    @Environment(AppStore.self) private var store

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 440), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose a provider")
                    .font(.system(size: 26, weight: .semibold))
                Text("Route your prompts through the gateway of your choice.")
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Provider.all) { provider in
                        ProviderCard(provider: provider)
                    }
                }
                .padding(.top, 20)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Concord")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("API keys & settings")
            }
        }
    }
}

struct ProviderCard: View {
    @Environment(AppStore.self) private var store
    let provider: Provider

    private var isAvailable: Bool { provider.status == .available }
    private var hasKey: Bool { store.hasKey(for: provider) }

    var body: some View {
        Button {
            store.open(provider)
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: provider.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(provider.tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
                statusBadge
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(provider.name)
                    .font(.headline)
                Text(provider.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if isAvailable {
                Label(hasKey ? "API key saved" : "No API key yet",
                      systemImage: hasKey ? "checkmark.circle.fill" : "key")
                    .font(.caption)
                    .foregroundStyle(hasKey ? Color.green : Color.secondary)
            } else {
                Text("Integration coming in a future version.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .opacity(isAvailable ? 1 : 0.62)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private var statusBadge: some View {
        if isAvailable {
            badge("Available", color: .green)
        } else {
            badge("Closed", color: .secondary)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}
