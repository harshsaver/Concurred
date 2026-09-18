import SwiftUI

/// Right-side inspector panel for network transport settings (custom User-Agent and an
/// optional HTTP/SOCKS5 proxy). Loads and saves its own `NetworkStore`.
struct NetworkPanel: View {
    @State private var store = NetworkStore()

    static let userAgentPresets: [(String, String)] = [
        ("Default (none)", ""),
        ("Chrome — macOS", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"),
        ("Safari — macOS", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"),
        ("Firefox — macOS", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:126.0) Gecko/20100101 Firefox/126.0"),
        ("Chrome — Windows", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"),
        ("Safari — iPhone", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1"),
        ("curl", "curl/8.4.0"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                userAgentCard(store)

                proxyCard(store)

                Text("Applied to all API requests. The User-Agent only changes the outgoing HTTP header — it has no effect on model output. A SOCKS5 proxy at 127.0.0.1:9050 works with a local Tor install (`brew install tor`).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button("Save") { store.save() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "network")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Network")
                    .font(.title3.weight(.semibold))
                Text("Transport for every API request")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Cards

    private func userAgentCard(_ store: NetworkStore) -> some View {
        NetworkCardBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("User-Agent", systemImage: "safari")
                    .font(.headline)

                HStack(spacing: 8) {
                    Menu("Presets") {
                        ForEach(Self.userAgentPresets, id: \.0) { preset in
                            Button(preset.0) { store.userAgent = preset.1 }
                        }
                    }
                    .fixedSize()
                    TextField("User-Agent", text: Binding(get: { store.userAgent }, set: { store.userAgent = $0 }), prompt: Text("Custom User-Agent (optional)"))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func proxyCard(_ store: NetworkStore) -> some View {
        NetworkCardBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Proxy", systemImage: "lock.shield")
                    .font(.headline)

                Toggle("Route through a proxy", isOn: Binding(get: { store.proxyEnabled }, set: { store.proxyEnabled = $0 }))

                if store.proxyEnabled {
                    Picker("Proxy type", selection: Binding(get: { store.proxyIsSOCKS }, set: { store.proxyIsSOCKS = $0 })) {
                        Text("HTTP").tag(false)
                        Text("SOCKS5").tag(true)
                    }
                    .pickerStyle(.segmented)

                    TextField("Host", text: Binding(get: { store.proxyHost }, set: { store.proxyHost = $0 }), prompt: Text("127.0.0.1"))
                        .textFieldStyle(.roundedBorder)

                    TextField("Port", text: Binding(get: { store.proxyPortText }, set: { store.proxyPortText = $0 }), prompt: Text("9050"))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}

/// A rounded card container used by the Network panel.
private struct NetworkCardBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.quaternary)
            )
    }
}
