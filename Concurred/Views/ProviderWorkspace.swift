import SwiftUI

/// A provider's workspace: a sidebar of saved chats next to the active chat.
struct ProviderWorkspace: View {
    @Environment(AppStore.self) private var appStore
    @Environment(ConversationStore.self) private var conversations
    let provider: Provider

    @State private var selection: Conversation.ID?

    var body: some View {
        Group {
            if !appStore.hasLoadedKey(for: provider) {
                ProgressView("Opening \(provider.name)…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let key = appStore.apiKey(for: provider) {
                HSplitView {
                    ConversationSidebar(provider: provider, selection: $selection)
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
                    detail(apiKey: key)
                        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                }
                .onAppear {
                    if selection == nil {
                        selection = conversations.list(for: provider.id).first?.id
                            ?? conversations.newOrReuseEmpty(providerID: provider.id, model: "").id
                    }
                }
            } else {
                MissingKeyView(provider: provider)
            }
        }
        .disabled(conversations.isReadBlocked)
        .navigationTitle(provider.name)
        .task(id: "\(provider.id)-\(appStore.keyStorage.rawValue)") {
            KeychainAccessPrompt.loadKey(for: provider, in: appStore)
        }
    }

    @ViewBuilder
    private func detail(apiKey: String) -> some View {
        if let id = selection, conversations.conversation(id) != nil {
            ChatDetail(viewModel: ChatViewModel(provider: provider, apiKey: apiKey, conversationID: id, store: conversations), apiKey: apiKey)
                .id(id)
        } else {
            EmptyWorkspaceView(provider: provider) {
                selection = conversations.newOrReuseEmpty(providerID: provider.id, model: "").id
            }
        }
    }
}

// MARK: - Sidebar

struct ConversationSidebar: View {
    @Environment(ConversationStore.self) private var store
    @Environment(AppStore.self) private var appStore
    let provider: Provider
    @Binding var selection: Conversation.ID?

    @State private var renamingID: Conversation.ID?
    @State private var renameText = ""
    @State private var deletingID: Conversation.ID?
    @State private var query = ""

    private var items: [Conversation] { store.list(for: provider.id) }

    private var filteredItems: [Conversation] {
        items.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.model.localizedCaseInsensitiveContains(query) }
    }

    private var currentModel: String {
        if let id = selection, let conversation = store.conversation(id) { return conversation.model }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Messages").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    query = ""
                    selection = store.newOrReuseEmpty(providerID: provider.id, model: currentModel).id
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .help("New chat (⌘N)")
                .accessibilityLabel("New chat")
                .keyboardShortcut("n", modifiers: .command)
                .disabled(store.isReadBlocked)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search conversations")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Clear search")
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 14).padding(.bottom, 12)

            if filteredItems.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: query.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                        .font(.system(size: 24, weight: .light))
                    Text(query.isEmpty ? "Your conversations start here" : "No matching conversations")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(20)
                Spacer()
            } else {
                List(selection: $selection) {
                    ForEach(filteredItems) { conversation in
                        ConversationRow(conversation: conversation, draft: store.draft(for: conversation.id))
                            .tag(conversation.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                            .contextMenu {
                                Button("Rename") {
                                    renameText = conversation.title
                                    renamingID = conversation.id
                                }
                                Button("Delete", role: .destructive) {
                                    deletingID = conversation.id
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            Divider().padding(.horizontal, 14)
            HStack(spacing: 10) {
                ProviderAvatar(provider: provider, size: 28)
                Menu {
                    ForEach(Provider.all) { option in
                        Button {
                            if option != provider { appStore.path = [.chat(option)] }
                        } label: {
                            Label(option.name, systemImage: option == provider ? "checkmark" : option.symbol)
                        }
                    }
                    Divider()
                    Button("All providers") { appStore.path = [] }
                } label: {
                    Text(provider.name).font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Switch provider")
                Spacer(minLength: 0)
                Button { appStore.showSettings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 15))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Settings").accessibilityLabel("Settings")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(.regularMaterial)
        .alert("Rename chat", isPresented: renamingBinding, presenting: renamingID) { id in
            TextField("Title", text: $renameText)
            Button("Save") {
                store.rename(id, to: renameText)
                renamingID = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { renamingID = nil }
        }
        .confirmationDialog("Delete this chat?", isPresented: Binding(
            get: { deletingID != nil }, set: { if !$0 { deletingID = nil } }
        ), titleVisibility: .visible, presenting: deletingID) { id in
            Button("Delete chat", role: .destructive) {
                delete(id)
                deletingID = nil
            }
        } message: { _ in Text("This removes the conversation from this Mac.") }
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
    var draft = ""

    private var preview: String {
        if !draft.isEmpty { return "Draft: " + draft }
        let latest = conversation.messages.last(where: { !$0.text.isEmpty })
        guard let latest else { return "Start a conversation" }
        return String(attributedMarkdown(String(latest.text.prefix(180))).characters)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private var dateLabel: String {
        let date = conversation.updatedAt
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PortraitAvatar(number: ConversationPortrait.number(for: conversation.id), size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(conversation.title.isEmpty ? "New message" : conversation.title)
                        .foregroundStyle(.primary)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(dateLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize()
                }
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundStyle(draft.isEmpty ? Color.secondary : Color.orange)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
        .help(conversation.title.isEmpty ? "New message" : conversation.title)
    }
}
