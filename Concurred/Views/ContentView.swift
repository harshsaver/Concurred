import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(ConversationStore.self) private var conversations

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $store.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case let .chat(provider):
                        ProviderWorkspace(provider: provider)
                            .id(provider.id)
                    }
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let error = conversations.errorText {
                VStack(alignment: .leading, spacing: 8) {
                    Label(error, systemImage: "externaldrive.badge.exclamationmark")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Retry") { conversations.retryPersistence() }
                        Button("Show saved chats file") {
                            NSWorkspace.shared.activateFileViewerSelecting([conversations.fileURL])
                        }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.15))
            }
        }
        .sheet(isPresented: $store.showSettings) {
            SettingsSheet()
        }
    }
}

struct HomeView: View {
    @Environment(AppStore.self) private var store
    private let columns = [GridItem(.flexible(), spacing: 20), GridItem(.flexible())]

    var body: some View {
        GeometryReader { geometry in
            let cardHeight = min(260, max(184, (geometry.size.height - 164) / 2))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 18) {
                        Image("AppLogo")
                            .resizable().scaledToFit()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Concurred").font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("Choose a provider to start a conversation.")
                                .font(.system(size: 14)).foregroundStyle(.secondary)
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(Provider.all) { provider in
                            ProviderCard(provider: provider, height: cardHeight)
                        }
                    }
                }
                .frame(maxWidth: 1120, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Concurred")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    .help("API keys and settings")
            }
        }
    }
}

private struct ProviderCard: View {
    @Environment(AppStore.self) private var store
    @State private var hovered = false
    let provider: Provider
    let height: CGFloat
    private var hasKey: Bool { store.hasKey(for: provider) }
    private var status: String {
        if hasKey { return "Ready" }
        if store.keyError(for: provider) != nil { return "Retry" }
        return store.hasLoadedKey(for: provider) ? "Add key" : "Open"
    }
    private var action: String {
        if store.keyError(for: provider) != nil { return "Retry access" }
        if store.hasLoadedKey(for: provider) && !hasKey { return "Add API key" }
        return "Open chat"
    }

    var body: some View {
        Button { store.open(provider) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: provider.symbol)
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(provider.tint.gradient, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    Spacer()
                    if store.hasLoadedKey(for: provider) {
                        Text(status)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(hasKey ? Color.green : Color.secondary)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background((hasKey ? Color.green : Color.primary).opacity(0.08), in: Capsule())
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name).font(.system(size: 20, weight: .semibold))
                    Text(provider.tagline).font(.system(size: 13)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack {
                    Text(action).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .fill(hovered ? provider.tint.opacity(0.06) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(hovered ? provider.tint.opacity(0.5) : Color.primary.opacity(0.1)))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(provider.name), \(status)")
    }
}
