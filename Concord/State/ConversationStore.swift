import Foundation
import Observation

/// Owns all saved conversations and persists them to disk as JSON.
///
/// Storage: `~/Library/Application Support/dev.october.concord/conversations.json`.
/// Only conversations that contain at least one message are written to disk;
/// freshly created empty chats live in memory for the session.
@MainActor
@Observable
final class ConversationStore {
    private(set) var conversations: [Conversation] = []

    private let fileURL: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("dev.october.concord", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("conversations.json")
        load()
        Log.chat("store loaded: \(conversations.count) conversations")
    }

    /// Conversations for one provider, most recently used first.
    func list(for providerID: String) -> [Conversation] {
        conversations
            .filter { $0.providerID == providerID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func conversation(_ id: Conversation.ID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    /// Reuses a trailing empty chat if there is one, otherwise creates a new chat.
    func newOrReuseEmpty(providerID: String, model: String) -> Conversation {
        if let existing = list(for: providerID).first, existing.messages.isEmpty {
            return existing
        }
        let now = Date()
        let conversation = Conversation(
            providerID: providerID,
            title: "",
            model: model,
            messages: [],
            createdAt: now,
            updatedAt: now
        )
        conversations.append(conversation)
        return conversation
    }

    func save(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
        } else {
            conversations.append(conversation)
        }
        persist()
    }

    func rename(_ id: Conversation.ID, to title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func delete(_ id: Conversation.ID) {
        conversations.removeAll { $0.id == id }
        persist()
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode([Conversation].self, from: data)
        else { return }
        conversations = decoded
    }

    private func persist() {
        let toSave = conversations.filter { !$0.messages.isEmpty }
        guard let data = try? Self.encoder.encode(toSave) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
