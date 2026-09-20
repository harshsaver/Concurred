import SwiftUI

struct NetworkPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = NetworkStore()

    @State private var previewPulse = 0

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                NetworkHeader(settings: store.draft, hasChanges: store.hasChanges)
                    .padding(.vertical, 6)
            }
            Section("User-Agent") {
                Menu(UserAgentPreset.matching(store.draft.userAgent).name) {
                    ForEach(UserAgentPreset.all) { preset in
                        Button {
                            store.settings.userAgent = preset.value
                            previewPulse += 1
                        } label: {
                            if store.settings.userAgent == preset.value {
                                Label(preset.name, systemImage: "checkmark")
                            } else {
                                Text(preset.name)
                            }
                        }
                    }
                }
                .accessibilityLabel("User-Agent presets")
                UserAgentPreview(preset: UserAgentPreset.matching(store.draft.userAgent), pulse: previewPulse)
                TextField("Custom User-Agent", text: $store.settings.userAgent,
                          prompt: Text("Enter a value or choose a preset"))
                    .labelsHidden()
                    .accessibilityLabel("Custom User-Agent")
                Text("Choose a preset or enter your own value, then save. Leave empty to use the system default.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Proxy") {
                Toggle("Route provider requests through a proxy", isOn: $store.settings.proxyEnabled)
                if store.settings.proxyEnabled {
                    Picker("Type", selection: $store.settings.proxyIsSOCKS) {
                        Text("HTTP").tag(false)
                        Text("SOCKS5").tag(true)
                    }
                    TextField("Host", text: $store.settings.proxyHost, prompt: Text("127.0.0.1"))
                    TextField("Port", text: $store.proxyPortText, prompt: Text("9050"))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.settings.proxyEnabled)
            Section {
                Text("Applies to model catalogs and chat requests after saving. TinyFish web searches use their own network connection and do not use this proxy.")
                    .font(.callout).foregroundStyle(.secondary)
                if let error = store.errorText ?? store.draft.validationError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text(store.hasChanges ? "Unsaved changes" : "Saved")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save") { store.save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.hasChanges || store.draft.validationError != nil)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Network")
    }
}

/// Describes configuration, not reachability: no connection checks or implied
/// privacy guarantees are attached to the mascot or its badge.
struct NetworkHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let settings: NetworkSettings
    let hasChanges: Bool

    private var portrait: Int {
        settings.proxyEnabled ? 43 : (settings.userAgent.isEmpty ? 31 : 20)
    }

    private var route: String {
        settings.proxyEnabled ? (settings.proxyIsSOCKS ? "SOCKS5 proxy" : "HTTP proxy") : "Direct connection"
    }

    private var symbol: String { settings.proxyEnabled ? "network" : "globe" }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                PortraitAvatar(number: portrait, size: 72)
                    .id(portrait)
                    .transition(.opacity)
            }
            .frame(width: 72, height: 72)
            .phaseAnimator(reduceMotion ? [false] : [false, true]) { content, lifted in
                content.offset(y: lifted ? -2 : 2)
            } animation: { _ in .easeInOut(duration: 2) }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.blue.gradient, in: Circle())
                    .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Network").font(.title3.weight(.semibold))
                Text(route).font(.callout.weight(.medium))
                Text(UserAgentPreset.matching(settings.userAgent).name)
                    .font(.caption).foregroundStyle(.secondary)
                if hasChanges {
                    Text("Preview · Save to apply")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: portrait)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: settings.proxyIsSOCKS)
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
    }
}
