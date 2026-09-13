import Observation
import SwiftUI

/// Drives a single OrcaRouter chat session, persisting it through the store.
@MainActor
@Observable
final class ChatViewModel {
    let provider: Provider
    let conversationID: Conversation.ID

    var messages: [ChatMessage] = []
    var input: String = ""
    var models: [String] = []
    var selectedModel: String = ""
    var isStreaming = false
    var errorText: String?
    /// True when the live `/models` catalog could not be loaded (fallback list shown).
    var modelsLoadFailed = false

    private let client: ChatClient
    private let store: ConversationStore
    private var streamTask: Task<Void, Never>?

    init(provider: Provider, apiKey: String, conversationID: Conversation.ID, store: ConversationStore) {
        self.provider = provider
        self.conversationID = conversationID
        self.store = store
        // A ChatViewModel is only created for integrated providers, which always have a baseURL.
        client = ChatClient(baseURL: provider.baseURL!, apiKey: apiKey, extraHeaders: provider.extraHeaders)
        models = provider.fallbackModels
        selectedModel = provider.fallbackModels.first ?? ""

        if let conversation = store.conversation(conversationID) {
            messages = conversation.messages
            if !conversation.model.isEmpty { selectedModel = conversation.model }
        }
    }

    var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    /// Loads the live catalog, keeping the fallback list if the request fails.
    func loadModels() async {
        do {
            let fetched = try await client.listModels()
            guard !fetched.isEmpty else { return }
            modelsLoadFailed = false
            var merged = fetched
            if !merged.contains(selectedModel) { merged.insert(selectedModel, at: 0) }
            models = merged
        } catch {
            modelsLoadFailed = true
        }
    }

    /// Selects an arbitrary model ID (typed by the user or from the catalog).
    func selectModel(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !models.contains(trimmed) { models.insert(trimmed, at: 0) }
        selectedModel = trimmed
        persist()
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        input = ""
        errorText = nil
        messages.append(ChatMessage(role: .user, text: text))
        messages.append(ChatMessage(role: .assistant, text: ""))
        let assistantIndex = messages.count - 1

        let history = messages[..<assistantIndex].map {
            WireMessage(role: $0.role.rawValue, content: $0.text)
        }
        let model = selectedModel
        persist() // save the question (and derive the title) before streaming starts

        Log.chat("send: provider=\(provider.id) model=\(model) history=\(history.count)")

        isStreaming = true
        streamTask = Task { [weak self, client] in
            // Coalesce deltas and flush to the UI at most ~20x/sec so fast/large
            // streams don't overwhelm the main thread with per-token view updates.
            var pending = ""
            var lastFlush = ContinuousClock.now
            var deltaCount = 0
            var totalChars = 0
            var flushCount = 0
            let started = Date()
            do {
                for try await delta in client.chatStream(model: model, messages: history) {
                    guard let self, assistantIndex < self.messages.count else { break }
                    pending += delta
                    deltaCount += 1
                    totalChars += delta.count
                    let now = ContinuousClock.now
                    if now - lastFlush >= .milliseconds(50) {
                        self.messages[assistantIndex].text += pending
                        pending = ""
                        flushCount += 1
                        lastFlush = now
                    }
                }
            } catch is CancellationError {
                // Stopped by the user — keep whatever streamed so far.
            } catch {
                self?.errorText = error.localizedDescription
                Log.error("stream error: \(error.localizedDescription)")
            }
            guard let self else { return }
            if !pending.isEmpty, assistantIndex < messages.count {
                messages[assistantIndex].text += pending
            }
            if assistantIndex < messages.count, messages[assistantIndex].text.isEmpty {
                messages.remove(at: assistantIndex)
            }
            isStreaming = false
            persist()
            Log.chat("stream done: \(deltaCount) deltas, \(totalChars) chars, \(flushCount) flushes in \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        persist()
    }

    private func persist() {
        let now = Date()
        var conversation = store.conversation(conversationID)
            ?? Conversation(
                id: conversationID,
                providerID: provider.id,
                title: "",
                model: selectedModel,
                messages: [],
                createdAt: now,
                updatedAt: now
            )
        conversation.messages = messages
        conversation.model = selectedModel
        if conversation.title.isEmpty { conversation.title = Self.title(from: messages) }
        conversation.updatedAt = now
        store.save(conversation)
    }

    static func title(from messages: [ChatMessage]) -> String {
        guard let first = messages.first(where: { $0.role == .user })?.text else { return "" }
        let flattened = first.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(flattened.prefix(48))
    }
}
