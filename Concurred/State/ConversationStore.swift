import Foundation
import Observation

/// The single owner of conversation state. A failed load must never be overwritten.
@MainActor
@Observable
final class ConversationStore {
    private(set) var conversations: [Conversation] = []
    private(set) var errorText: String?
    private(set) var isReadBlocked = false
    private var drafts: [Conversation.ID: String] = [:]
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.october.concord/conversations.json")
        load()
    }

    func list(for providerID: String) -> [Conversation] {
        conversations.filter { $0.providerID == providerID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func conversation(_ id: Conversation.ID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    func newOrReuseEmpty(providerID: String, model: String) -> Conversation {
        if let existing = list(for: providerID).first(where: { $0.messages.isEmpty }) {
            return existing
        }
        let now = Date()
        let conversation = Conversation(providerID: providerID, title: "", model: model,
                                        messages: [], createdAt: now, updatedAt: now)
        conversations.append(conversation)
        return conversation
    }

    func draft(for id: Conversation.ID) -> String { drafts[id] ?? "" }

    func setDraft(_ text: String, for id: Conversation.ID) {
        guard conversation(id) != nil else { return }
        drafts[id] = text.isEmpty ? nil : text
    }

    func save(_ conversation: Conversation) {
        // A late response must not resurrect a deleted conversation.
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        conversations[index] = conversation
        persist()
    }

    func rename(_ id: Conversation.ID, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = title
        persist()
    }

    func delete(_ id: Conversation.ID) {
        conversations.removeAll { $0.id == id }
        drafts[id] = nil
        persist()
    }

    func retryPersistence() {
        if isReadBlocked { load() } else { persist() }
    }

    private func load() {
        do {
            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch CocoaError.fileReadNoSuchFile {
                conversations = []
                isReadBlocked = false
                errorText = nil
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([Conversation].self, from: data)
            guard Set(loaded.map(\.id)).count == loaded.count,
                  loaded.allSatisfy({ Set($0.messages.map(\.id)).count == $0.messages.count }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            conversations = loaded
            isReadBlocked = false
            errorText = nil
        } catch {
            isReadBlocked = true
            errorText = "Saved chats could not be opened. The existing file has been kept intact. \(error.localizedDescription)"
        }
    }

    private func persist() {
        guard !isReadBlocked else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(conversations.filter { !$0.messages.isEmpty })
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            errorText = nil
        } catch {
            errorText = "Your latest chat changes have not been saved. \(error.localizedDescription)"
        }
    }
}
