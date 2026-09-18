import Foundation

/// Minimal client for any OpenAI-compatible gateway (OrcaRouter, OpenRouter, Featherless).
/// Uses `POST {base}/chat/completions` (SSE) and `GET {base}/models`.
struct ChatClient: Sendable {
    enum ClientError: LocalizedError {
        case invalidResponse
        case http(status: Int, message: String)
        case api(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The server returned an unexpected response."
            case let .api(message):
                return message
            case let .http(status, message):
                let clean = Self.cleanMessage(from: message)
                switch status {
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
        let (data, response) = try await NetworkConfig.session().data(for: makeRequest(path: "models"))
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ClientError.http(status: http.statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }
        let list = try JSONDecoder().decode(ModelList.self, from: data)
        return list.data.map(\.id).sorted()
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

                    let (bytes, response) = try await NetworkConfig.session().bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ClientError.invalidResponse
                    }
                    guard (200 ..< 300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw ClientError.http(status: http.statusCode, message: body)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count)
                            .trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        // Some gateways deliver errors in-band (HTTP 200 + SSE error event).
                        if let envelope = try? JSONDecoder().decode(StreamErrorEnvelope.self, from: data),
                           let message = envelope.error?.message {
                            throw ClientError.api(message)
                        }
                        if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                           let delta = chunk.choices.first?.delta.content {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
