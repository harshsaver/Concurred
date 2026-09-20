import Foundation

/// Streaming chat and model catalogs for the configured provider.
/// Uses `POST {base}/chat/completions` (SSE) and `GET {base}/models`.
struct ChatClient: Sendable {
    enum ClientError: LocalizedError {
        case invalidResponse
        case http(status: Int, message: String)
        case api(String)
        case interrupted

        var errorDescription: String? {
            switch self {
            case .interrupted:
                return "The response ended unexpectedly. You can retry the reply."
            case .invalidResponse:
                return "The server returned an unexpected response."
            case let .api(message):
                return message
            case let .http(status, message):
                let clean = Self.cleanMessage(from: message)
                switch status {
                case 300..<400: return "The provider redirected the request. Check the configured provider endpoint."
                case 403: return "Access denied. Check your API key permissions and model access."
                case 401: return "Invalid or missing API key. Check it in Settings."
                case 402: return "Payment required — check your account credit."
                case 404: return clean.isEmpty ? "Model not found. Check the model ID." : clean
                case 429: return "Rate limited — please slow down and try again."
                case 500, 502, 503, 504:
                    return clean.isEmpty
                        ? "The provider is temporarily unavailable. Try again, or switch model/provider."
                        : clean
                default:
                    return clean.isEmpty ? "Request failed (\(status))." : clean
                }
            }
        }

        /// Pulls the human-readable message out of an OpenAI-style error body
        /// (`{"error":{"message":"…"}}`), dropping request-id noise — instead of dumping raw JSON.
        static func cleanMessage(from body: String) -> String {
            if let data = body.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                if let range = message.range(of: " (request id:") {
                    return String(message[..<range.lowerBound])
                }
                return message
            }
            return String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        }
    }

    let baseURL: URL
    let apiKey: String
    var extraHeaders: [String: String] = [:]
    var makeSession: @Sendable () throws -> URLSession = { try NetworkConfig.session() }

    private func makeRequest(path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    /// Fetches the live model catalog.
    func listModels() async throws -> [String] {
        let session = try makeSession()
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: makeRequest(path: "models"))
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ClientError.http(status: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }
        let list = try JSONDecoder().decode(ModelList.self, from: data)
        return Array(Set(list.data.map(\.id).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
    }

    /// Streams a chat completion, yielding assistant content deltas as they arrive (SSE).
    func chatStream(model: String, messages: [WireMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = makeRequest(path: "chat/completions")
                    request.httpMethod = "POST"
                    request.httpBody = try JSONEncoder().encode(
                        ChatRequest(model: model, messages: messages, stream: true)
                    )

                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    try Task.checkCancellation()
                    let session = try makeSession()
                    defer { session.invalidateAndCancel() }
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ClientError.invalidResponse
                    }
                    guard (200 ..< 300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count >= 16_384 { break }
                        }
                        throw ClientError.http(status: http.statusCode, message: String(decoding: body, as: UTF8.self))
                    }

                    guard http.mimeType?.lowercased() == "text/event-stream" else {
                        throw ClientError.invalidResponse
                    }
                    var parser = ServerSentEvents()
                    var finished = false
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        guard let payload = try parser.append(byte), !payload.isEmpty else { continue }
                        if payload.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                            finished = true
                            break
                        }
                        let event = try Self.decodeEvent(payload)
                        if let content = event.content { continuation.yield(content) }
                        if event.finished { finished = true }
                    }
                    try Task.checkCancellation()
                    guard finished else { throw ClientError.interrupted }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func decodeEvent(_ payload: String) throws -> (content: String?, finished: Bool) {
        let data = Data(payload.utf8)
        if let envelope = try? JSONDecoder().decode(StreamErrorEnvelope.self, from: data),
           let error = envelope.error {
            throw ClientError.api(error.message ?? "The provider could not complete the response.")
        }
        let chunk: StreamChunk
        do { chunk = try JSONDecoder().decode(StreamChunk.self, from: data) }
        catch { throw ClientError.invalidResponse }
        guard let choice = chunk.choices.first(where: { $0.index == nil || $0.index == 0 }) else {
            return (nil, false) // usage-only event
        }
        if choice.finish_reason == "error" { throw ClientError.api("The provider could not complete the response.") }
        return (choice.delta?.content, choice.finish_reason != nil)
    }

}
