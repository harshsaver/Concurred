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
    /// When on, the next reply is grounded in live web search (TinyFish).
    var groundWithSearch = false
    /// When on, real personal info is swapped for the alt identity before sending, and
    /// swapped back in the reply for display. The gateway only ever sees the fake identity.
    var cloak = false
    /// Per-conversation swap record (realValue → altValue); persists across turns so
    /// cloaking stays consistent and the reply can be reliably un-cloaked.
    private var cloakVault: [String: String] = [:]
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

        let grounding = groundWithSearch
        let query = text
        // Capture the cloak state and load the identity once per send (avoids repeated
        // Keychain reads inside the stream loop). The user's own displayed message stays real.
        let cloakOn = cloak
        let identity = cloakOn ? AltIdentity.load() : .empty

        isStreaming = true
        streamTask = Task { [weak self, client] in
            // Optionally ground the answer in live web search (TinyFish) before streaming.
            var wire = history
            if grounding {
                let results = await WebSearchService.search(query)
                if !results.isEmpty {
                    let block = results
                        .map { "- \($0.title)\n  \($0.url)\n  \($0.snippet)" }
                        .joined(separator: "\n")
                    wire.insert(WireMessage(role: "system", content:
                        "Use these live web search results to ground your answer, and cite the source URLs where relevant.\n\nWeb results:\n\(block)"), at: 0)
                    Log.chat("grounded with \(results.count) web results")
                }
            }
            // Cloak every outgoing message (real → fake) so the gateway only sees the alt
            // identity. The grounding system message (web results) is left untouched. The
            // shared vault keeps prior turns cloaked consistently across the whole history.
            if cloakOn, let self {
                wire = wire.map { message in
                    message.role == "system"
                        ? message
                        : WireMessage(
                            role: message.role,
                            content: Cloaker.cloak(message.content, identity: identity, vault: &self.cloakVault)
                        )
                }
                Log.chat("cloaked \(wire.count) message(s); vault has \(self.cloakVault.count) entries")
            }
            // Coalesce deltas and flush to the UI at most ~20x/sec so fast/large
            // streams don't overwhelm the main thread with per-token view updates.
            // When cloaking, `raw` accumulates the un-modified (cloaked) reply so fake
            // values split across tokens still un-cloak correctly on each flush.
            var pending = ""
            var raw = ""
            var lastFlush = ContinuousClock.now
            var deltaCount = 0
            var totalChars = 0
            var flushCount = 0
            var cancelled = false
            let started = Date()
            do {
                for try await delta in client.chatStream(model: model, messages: wire) {
                    guard let self, assistantIndex < self.messages.count else { break }
                    pending += delta
                    raw += delta
                    deltaCount += 1
                    totalChars += delta.count
                    let now = ContinuousClock.now
                    if now - lastFlush >= .milliseconds(50) {
                        if cloakOn {
                            self.messages[assistantIndex].text = Cloaker.uncloak(raw, vault: self.cloakVault)
                        } else {
                            self.messages[assistantIndex].text += pending
                        }
                        pending = ""
                        flushCount += 1
                        lastFlush = now
                    }
                }
            } catch is CancellationError {
                cancelled = true // Stopped by the user — keep whatever streamed so far.
            } catch {
                self?.errorText = error.localizedDescription
                Log.error("stream error: \(error.localizedDescription)")
            }
            guard let self else { return }
            if assistantIndex < messages.count {
                if cloakOn {
                    // Set the full un-cloaked text (idempotent) so a trailing partial or an
                    // un-flushed short reply displays correctly.
                    messages[assistantIndex].text = Cloaker.uncloak(raw, vault: cloakVault)
                } else if !pending.isEmpty {
                    messages[assistantIndex].text += pending
                }
            }
            let empty = assistantIndex < messages.count && messages[assistantIndex].text.isEmpty
            if empty, assistantIndex < messages.count {
                messages.remove(at: assistantIndex)
            }
            // A 200 stream that produced no content and no error still means "it didn't work".
            if empty, !cancelled, errorText == nil {
                errorText = "\(selectedModel) returned an empty response — it may be unavailable, gated, or unsupported on \(provider.name). Try another model."
                Log.error("empty response: model=\(selectedModel) provider=\(provider.id)")
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
