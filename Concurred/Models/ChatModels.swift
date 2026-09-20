import Foundation

/// A single message rendered in the chat transcript.
struct ChatMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable {
        case system, user, assistant
    }

    var id = UUID()
    let role: Role
    var text: String
}

/// A saved conversation with one provider.
struct Conversation: Identifiable, Equatable, Codable {
    var id = UUID()
    var providerID: String
    var title: String
    var model: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - Wire types (OpenAI-compatible)

struct WireMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct ChatRequest: Encodable, Sendable {
    let model: String
    let messages: [WireMessage]
    let stream: Bool
}

/// A single server-sent chunk from a streaming completion.
struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let index: Int?
        let delta: Delta?
        let finish_reason: String?
    }
    let choices: [Choice]
}

/// Response shape for `GET /v1/models`.
struct ModelList: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

/// Some gateways (notably OpenRouter) deliver errors as an SSE event with HTTP 200,
/// e.g. `data: {"error":{"message":"No endpoints found..."}}`. Decoded to surface them.
struct StreamErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String? }
    let error: APIError?
}
