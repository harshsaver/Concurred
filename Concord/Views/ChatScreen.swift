import AppKit
import SwiftUI

/// A provider's workspace: a sidebar of saved chats next to the active chat.
struct ProviderWorkspace: View {
    @Environment(AppStore.self) private var appStore
    @Environment(ConversationStore.self) private var conversations
    let provider: Provider

    @State private var selection: Conversation.ID?

    private var defaultModel: String { provider.fallbackModels.first ?? "" }

    var body: some View {
        Group {
            if let key = appStore.apiKey(for: provider) {
                HStack(spacing: 0) {
                    ConversationSidebar(provider: provider, selection: $selection)
                        .frame(width: 250)
                    Divider()
                    detail(apiKey: key)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .onAppear {
                    if selection == nil {
                        selection = conversations.list(for: provider.id).first?.id
                            ?? conversations.newOrReuseEmpty(providerID: provider.id, model: defaultModel).id
                    }
                }
            } else {
                MissingKeyView(provider: provider)
            }
        }
        .navigationTitle(provider.name)
    }

    @ViewBuilder
    private func detail(apiKey: String) -> some View {
        if let id = selection, conversations.conversation(id) != nil {
            ChatDetail(provider: provider, apiKey: apiKey, conversationID: id, store: conversations)
                .id(id)
        } else {
            EmptyWorkspaceView(provider: provider) {
                selection = conversations.newOrReuseEmpty(providerID: provider.id, model: defaultModel).id
            }
        }
    }
}

// MARK: - Sidebar

struct ConversationSidebar: View {
    @Environment(ConversationStore.self) private var store
    let provider: Provider
    @Binding var selection: Conversation.ID?

    @State private var renamingID: Conversation.ID?
    @State private var renameText = ""

    private var items: [Conversation] { store.list(for: provider.id) }

    private var currentModel: String {
        if let id = selection, let conversation = store.conversation(id) { return conversation.model }
        return provider.fallbackModels.first ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chats").font(.headline)
                Spacer()
                Button {
                    selection = store.newOrReuseEmpty(providerID: provider.id, model: currentModel).id
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("New chat")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if items.isEmpty {
                Spacer()
                Text("No chats yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(selection: $selection) {
                    ForEach(items) { conversation in
                        ConversationRow(conversation: conversation)
                            .tag(conversation.id)
                            .contextMenu {
                                Button("Rename") {
                                    renameText = conversation.title
                                    renamingID = conversation.id
                                }
                                Button("Delete", role: .destructive) {
                                    delete(conversation.id)
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .alert("Rename chat", isPresented: renamingBinding) {
            TextField("Title", text: $renameText)
            Button("Save") {
                if let id = renamingID { store.rename(id, to: renameText) }
                renamingID = nil
            }
            Button("Cancel", role: .cancel) { renamingID = nil }
        }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renamingID != nil }, set: { if !$0 { renamingID = nil } })
    }

    private func delete(_ id: Conversation.ID) {
        store.delete(id)
        if selection == id { selection = items.first?.id }
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(conversation.title.isEmpty ? "New chat" : conversation.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(conversation.model)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Chat detail

/// Which right-side inspector panel is currently shown on the chat page.
enum ChatPanel {
    case altID
    case network
}

struct ChatDetail: View {
    @Environment(AppStore.self) private var appStore
    @State private var vm: ChatViewModel
    let provider: Provider

    @State private var showModelEntry = false
    @State private var modelDraft = ""
    @State private var activePanel: ChatPanel?

    init(provider: Provider, apiKey: String, conversationID: Conversation.ID, store: ConversationStore) {
        self.provider = provider
        _vm = State(initialValue: ChatViewModel(
            provider: provider, apiKey: apiKey, conversationID: conversationID, store: store
        ))
    }

    private let bottomAnchor = "bottom-anchor"

    var body: some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            if let error = vm.errorText {
                ErrorBanner(text: error) { vm.errorText = nil }
            }
            transcript
            inputBar
        }
        .toolbar {
            ToolbarItem(placement: .principal) { modelPicker }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { activePanel = .altID } label: {
                    Label("Cloak / Alt ID", systemImage: "person.badge.shield.checkmark")
                }
                .help("Alt ID & Cloak")

                Button { activePanel = .network } label: {
                    Label("Network", systemImage: "network")
                }
                .help("Network settings")

                Button { appStore.showSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("API keys & settings")
            }
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
                }
                .padding(10)

                Group {
                    switch activePanel {
                    case .altID: AltIDPanel()
                    case .network: NetworkPanel()
                    case nil: Color.clear
                    }
                }
            }
            .inspectorColumnWidth(min: 320, ideal: 400, max: 640)
        }
        .task { await vm.loadModels() }
        .alert("Model ID", isPresented: $showModelEntry) {
            TextField("provider/model-id", text: $modelDraft)
            Button("Use") { vm.selectModel(modelDraft) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter any model ID served by \(provider.name). It's sent verbatim as the model — e.g. openai/gpt-4o-mini or obsidian/Qwen3.8-27B. The provider validates it when you send.")
        }
    }

    /// Drives the single `.inspector`: presented whenever a panel is selected, and
    /// clearing the selection on dismiss.
    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { activePanel != nil },
            set: { if !$0 { activePanel = nil } }
        )
    }

    private var modelPicker: some View {
        Menu {
            Button {
                modelDraft = vm.selectedModel
                showModelEntry = true
            } label: {
                Label("Enter model ID…", systemImage: "pencil")
            }
            Divider()
            ForEach(vm.models, id: \.self) { model in
                Button {
                    vm.selectModel(model)
                } label: {
                    if model == vm.selectedModel {
                        Label(model, systemImage: "checkmark")
                    } else {
                        Text(model)
                    }
                }
            }
            if vm.modelsLoadFailed {
                Divider()
                Text("⚠︎ Couldn't load the full catalog — showing defaults.")
            }
        } label: {
            HStack(spacing: 5) {
                Text(vm.selectedModel).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
        }
        .frame(maxWidth: 320)
        .disabled(vm.isStreaming)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            // A List (NSTableView-backed) virtualizes rows properly and avoids the
            // LazyVStack layout loop that was spinning on scroll.
            List {
                if vm.messages.isEmpty {
                    EmptyChatView(provider: provider)
                        .padding(.top, 64)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                ForEach(vm.messages) { message in
                    MessageRow(
                        message: message,
                        tint: provider.tint,
                        isLive: vm.isStreaming
                            && message.role == .assistant
                            && message.id == vm.messages.last?.id
                    )
                    .id(message.id)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 7, leading: 20, bottom: 7, trailing: 20))
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
            .onChange(of: vm.messages.last?.text) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
            .onChange(of: vm.messages.count) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        @Bindable var vm = vm
        return HStack(alignment: .bottom, spacing: 10) {
            Toggle(isOn: $vm.groundWithSearch) {
                Label("Ground", systemImage: "globe")
            }
            .toggleStyle(.checkbox)
            .help("Ground answers in live web search (TinyFish)")
            .padding(.bottom, 6)

            Toggle(isOn: $vm.cloak) {
                Label("Cloak", systemImage: "eye.slash")
            }
            .toggleStyle(.checkbox)
            .help("Swap your real info for your Alt ID before sending")
            .padding(.bottom, 6)

            TextField("Message \(provider.name)…", text: $vm.input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 6)
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.quaternary)
                )

            if vm.isStreaming {
                Button(role: .destructive) {
                    vm.stop()
                } label: {
                    Image(systemName: "stop.circle.fill").font(.title)
                }
                .buttonStyle(.plain)
                .help("Stop")
            } else {
                Button {
                    vm.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .buttonStyle(.plain)
                .foregroundStyle(vm.canSend ? provider.tint : Color.secondary)
                .disabled(!vm.canSend)
                .keyboardShortcut(.return, modifiers: [])
                .help("Send")
            }
        }
        .padding(14)
        .background(.bar)
    }
}

// MARK: - Rows & helper views

struct MessageRow: View {
    let message: ChatMessage
    let tint: Color
    /// True only for the assistant message that is currently streaming — rendered as
    /// plain text so we don't re-parse Markdown on every token.
    var isLive: Bool = false

    /// While streaming we show only the tail of very long output, so a single growing
    /// `Text` can't blow up layout cost. The full text is kept in the model.
    private static let streamingTailLimit = 8000

    private var isUser: Bool { message.role == .user }

    private var streamingText: String {
        message.text.count > Self.streamingTailLimit
            ? "…" + String(message.text.suffix(Self.streamingTailLimit))
            : message.text
    }

    @State private var copied = false

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                bubble
                if !message.text.isEmpty, !isLive {
                    Button(action: copyMessage) {
                        Label(copied ? "Copied" : "Copy",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy this message")
                    .padding(isUser ? .trailing : .leading, 2)
                }
            }
            if !isUser { Spacer(minLength: 48) }
        }
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            copied = false
        }
    }

    /// Cap what any single row draws so scrolling stays cheap.
    private var displayText: String {
        let text = isLive ? streamingText : message.text
        let cap = 8000
        return text.count > cap ? String(text.prefix(cap)) + "…" : text
    }

    @ViewBuilder private var bubble: some View {
        if message.text.isEmpty, message.role == .assistant {
            ProgressView()
                .controlSize(.small)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: 640, alignment: .leading)
        } else if isUser {
            Text(displayText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(Color.white)
                .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: 640, alignment: .trailing)
        } else {
            // One attributed Text per message (Markdown formatting) — cheap and safe in a
            // List. While streaming we render plain text so we don't re-parse per token.
            Group {
                if isLive {
                    Text(displayText)
                } else {
                    Text(attributedMarkdown(displayText))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .frame(maxWidth: 640, alignment: .leading)
            .lineSpacing(3)
        }
    }
}

struct EmptyChatView: View {
    let provider: Provider

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: provider.symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(provider.tint)
            Text("Chat with \(provider.name)")
                .font(.title3.weight(.semibold))
            Text("Pick a model above, then send a message to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 380)
    }
}

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
            Text("Add your \(provider.name) API key")
                .font(.title3.weight(.semibold))
            Text("Concord needs an API key to talk to \(provider.name). Keys are stored securely in your macOS Keychain.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
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
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.callout).lineLimit(3)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .foregroundStyle(.white)
        .background(Color.red.opacity(0.92))
    }
}
