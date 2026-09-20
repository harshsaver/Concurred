import AppKit
import SwiftUI

// MARK: - Chat detail

/// Which right-side inspector panel is currently shown on the chat page.
enum ChatPanel {
    case altID
    case network
}

struct ChatDetail: View {
    @Environment(AppStore.self) private var appStore
    @Environment(ConversationStore.self) private var conversations
    @State private var vm: ChatViewModel
    let provider: Provider

    @State private var followReply = true
    @State private var composerFocused = true
    let apiKey: String
    @State private var activePanel: ChatPanel?
    @State private var cloakReview: CloakReview?

    init(viewModel: ChatViewModel, apiKey: String) {
        provider = viewModel.provider
        self.apiKey = apiKey
        _vm = State(initialValue: viewModel)
    }

    private let bottomAnchor = "bottom-anchor"

    var body: some View {
        VStack(spacing: 0) {
            conversationHeader
            if let error = vm.errorText {
                ErrorBanner(text: error, retry: vm.canRetry ? { vm.retry() } : nil) { vm.errorText = nil }
            }
            if vm.messages.isEmpty {
                Spacer(minLength: 0)
            } else {
                transcript
            }
            inputBar
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(item: $cloakReview) { review in
            CloakReviewSheet(review: review, usesSearch: vm.groundWithSearch) { vm.send(review: $0) }
        }
        .inspector(isPresented: inspectorPresented) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { activePanel = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                    .accessibilityLabel("Close panel")
                }
                .padding(10)

                Group {
                    switch activePanel {
                    case .altID: AltIDPanel(cloakEnabled: Binding(get: { vm.cloak }, set: { vm.cloak = $0 }))
                    case .network: NetworkPanel()
                    case nil: Color.clear
                    }
                }
            }
            .inspectorColumnWidth(min: 320, ideal: 400, max: 640)
        }
        .task(id: apiKey) {
            vm.updateAPIKey(apiKey)
            await vm.loadModels()
        }
        .onAppear { composerFocused = true }
        .onDisappear { vm.stop() }

    }

    /// Drives the single `.inspector`: presented whenever a panel is selected, and
    /// clearing the selection on dismiss.
    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { activePanel != nil },
            set: { if !$0 { activePanel = nil } }
        )
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            // A List (NSTableView-backed) virtualizes rows properly and avoids the
            // LazyVStack layout loop that was spinning on scroll.
            List {
                if !vm.messages.isEmpty, let conversation = conversations.conversation(vm.conversationID) {
                    Text("Started \(conversation.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                }
                ForEach(vm.messages) { message in
                    MessageRow(
                        message: message,
                        isLive: vm.isStreaming
                            && message.role == .assistant
                            && message.id == vm.messages.last?.id,
                        isSearching: vm.isSearching
                    )
                    .id(message.id)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 24, bottom: 5, trailing: 24))
                    .listRowBackground(Color.clear)
                }
                Color.clear.frame(height: 1)
                    .id(bottomAnchor)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(TranscriptScrollObserver {
                if !vm.messages.isEmpty { followReply = false }
            })
            .onChange(of: vm.messages.last?.text) {
                if followReply { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
            .onChange(of: vm.messages.last?.id) {
                if vm.isStreaming { followReply = true }
                if followReply { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            .onChange(of: followReply) {
                if followReply { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
        }
    }

    private var conversationHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                conversationIdentity.frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                ModelPicker(vm: vm).frame(width: 240)
                conversationTools
            }
            VStack(alignment: .leading, spacing: 10) {
                conversationIdentity
                HStack(spacing: 12) {
                    ModelPicker(vm: vm)
                    Spacer(minLength: 0)
                    conversationTools
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private var conversationIdentity: some View {
        HStack(spacing: 9) {
            PortraitAvatar(number: ConversationPortrait.number(for: vm.conversationID), size: 30)
            let title = conversations.conversation(vm.conversationID)?.title ?? ""
            Text(title.isEmpty ? "New message" : title)
                .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                .help(title.isEmpty ? "New message" : title)
        }
    }

    private var conversationTools: some View {
        HStack(spacing: 8) {
            Button("Alt ID", systemImage: "person.crop.circle") {
                activePanel = activePanel == .altID ? nil : .altID
            }
            .tint(activePanel == .altID ? .blue : .secondary)
            .help("Edit your alternate identity")
            Button("Network", systemImage: "network") {
                activePanel = activePanel == .network ? nil : .network
            }
            .tint(activePanel == .network ? .blue : .secondary)
            .help("Proxy and User-Agent settings")
            Link(destination: provider.docsURL) {
                Label("Provider documentation", systemImage: "questionmark.circle")
                    .labelStyle(.iconOnly)
            }
            .help("Provider documentation")
            Button { appStore.showSettings = true } label: {
                Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly)
            }
            .help("Settings")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.system(size: 11, weight: .medium))
        .fixedSize()
    }

    private var inputBar: some View {
        @Bindable var vm = vm
        return VStack(spacing: 9) {
            HStack(alignment: .bottom, spacing: 10) {
                MessageComposer(text: $vm.input, focused: $composerFocused,
                                placeholder: "Message \(provider.name)", onSend: { vm.send() })
                    .overlay(alignment: .topLeading) {
                        if vm.input.isEmpty {
                            Text("Message \(provider.name)")
                                .font(.system(size: 14)).foregroundStyle(.secondary)
                                .padding(.top, 5).allowsHitTesting(false)
                        }
                    }
                if vm.isStreaming {
                    Button { vm.stop() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.blue, in: Circle())
                    }
                    .buttonStyle(.plain).help("Stop reply")
                    .accessibilityLabel("Stop reply")
                } else {
                    Button { vm.send() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(vm.canSend ? Color.white : Color.secondary)
                            .frame(width: 28, height: 28)
                            .background(vm.canSend ? Color.blue : Color.primary.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!vm.canSend)
                    .help("Send (Return or ⌘Return)")
                    .accessibilityLabel("Send message")
                }
            }
            .padding(.leading, 15).padding(.trailing, 7).padding(.vertical, 6)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20)
                .strokeBorder(composerFocused ? Color.blue.opacity(0.45) : Color.primary.opacity(0.16)))

            HStack(spacing: 7) {
                Toggle(isOn: $vm.groundWithSearch) { Label("Web search", systemImage: "globe") }
                    .help("Ground this reply with TinyFish. Uses a separate connection from the provider proxy.")
                Toggle(isOn: $vm.cloak) { Label("Cloak", systemImage: "eye.slash") }
                    .help("Replace configured and recognized personal values before sending. Edit details in Alt ID.")
                    .contextMenu { Button("Edit Alt ID") { activePanel = .altID } }
                if vm.cloak {
                    Button("Review Cloak", systemImage: "eye") {
                        do { cloakReview = try vm.makeCloakReview() }
                        catch { vm.errorText = error.localizedDescription }
                    }
                    .buttonStyle(.plain).disabled(!vm.canSend)
                    .help("Preview outgoing text and find more identifiers on this Mac")
                }
                Spacer(minLength: 4)
                if !vm.messages.isEmpty {
                    Button("Retry", systemImage: "arrow.clockwise") { vm.retry() }
                        .buttonStyle(.plain)
                        .disabled(!vm.canRetry)
                        .help("Generate a new reply to your last message")
                    Toggle(isOn: $followReply) {
                        Label(followReply ? "Follow" : "Jump to latest", systemImage: "arrow.down.to.line")
                    }
                    .help("Automatically scroll to the latest reply")
                } else if vm.selectedModel.isEmpty {
                    Text("Choose a model above").foregroundStyle(.secondary)
                } else {
                    Text("Return to send · ⇧Return for a new line").foregroundStyle(.secondary)
                }
            }
            .toggleStyle(ChatOptionToggleStyle())
            .font(.system(size: 10))
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 10)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Rows & helper views

struct EmptyWorkspaceView: View {
    let provider: Provider
    let onNewChat: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: provider.symbol)
                .font(.system(size: 38))
                .foregroundStyle(provider.tint)
            Text("No chat selected")
                .font(.title3.weight(.semibold))
            Text("Start a new conversation with \(provider.name).")
                .foregroundStyle(.secondary)
            Button(action: onNewChat) {
                Label("New chat", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MissingKeyView: View {
    @Environment(AppStore.self) private var store
    let provider: Provider

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 34))
                .foregroundStyle(provider.tint)
            Text(store.keyError(for: provider) == nil ? "Add your \(provider.name) API key" : "Couldn't load your \(provider.name) key")
                .font(.title3.weight(.semibold))
            Text(store.keyError(for: provider) ?? "Concurred needs an API key to talk to \(provider.name). Add it in Settings. Storage: \(store.keyStorage.title).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            if store.keyError(for: provider) != nil {
                Button("Retry key access") {
                    KeychainAccessPrompt.loadKey(for: provider, in: store, retry: true)
                }
            }
            Button {
                store.showSettings = true
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorBanner: View {
    let text: String
    var retry: (() -> Void)? = nil
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 4)
            if let retry { Button("Retry", action: retry).buttonStyle(.borderless) }
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .foregroundStyle(.primary)
        .background(Color.red.opacity(0.08))
    }
}
