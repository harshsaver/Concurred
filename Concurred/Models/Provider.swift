import SwiftUI

/// A model-routing provider the app can talk to.
struct Provider: Identifiable, Hashable {
    let id: String
    let name: String
    let tagline: String
    let symbol: String       // SF Symbol
    let tint: Color
    let docsURL: URL
    let apiKeysURL: URL?
    let keyPlaceholder: String

    let baseURL: URL
    let extraHeaders: [String: String]

    static func == (lhs: Provider, rhs: Provider) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Provider {
    static let orcarouter = Provider(
        id: "orcarouter",
        name: "OrcaRouter",
        tagline: "Access models through a single gateway.",
        symbol: "fish.fill",
        tint: Color(red: 0.10, green: 0.55, blue: 0.72),
        docsURL: URL(string: "https://docs.orcarouter.ai")!,
        apiKeysURL: URL(string: "https://www.orcarouter.ai")!,
        keyPlaceholder: "sk-orca-…",
        baseURL: URL(string: "https://api.orcarouter.ai/v1")!,
        extraHeaders: [:]
    )

    static let openrouter = Provider(
        id: "openrouter",
        name: "OpenRouter",
        tagline: "A unified interface for LLMs.",
        symbol: "arrow.triangle.branch",
        tint: Color(red: 0.37, green: 0.35, blue: 0.85),
        docsURL: URL(string: "https://openrouter.ai/docs")!,
        apiKeysURL: URL(string: "https://openrouter.ai/keys")!,
        keyPlaceholder: "sk-or-…",
        baseURL: URL(string: "https://openrouter.ai/api/v1")!,
        extraHeaders: [
            "X-Title": "Concurred",
        ]
    )

    static let featherless = Provider(
        id: "featherless",
        name: "Featherless",
        tagline: "Serverless inference for open models.",
        symbol: "wind",
        tint: Color(red: 0.91, green: 0.42, blue: 0.56),
        docsURL: URL(string: "https://featherless.ai/docs")!,
        apiKeysURL: URL(string: "https://featherless.ai")!,
        keyPlaceholder: "rc_…",
        baseURL: URL(string: "https://api.featherless.ai/v1")!,
        extraHeaders: [:]
    )

    static let concurred = Provider(
        id: "concurred",
        name: "Concurred",
        tagline: "Chat through the Concurred gateway.",
        symbol: "checkmark.seal.fill",
        tint: Color(red: 0.20, green: 0.66, blue: 0.44),
        docsURL: URL(string: "https://concurred.ai/docs/api")!,
        apiKeysURL: URL(string: "https://concurred.ai/dashboard")!,
        keyPlaceholder: "ck_…",
        baseURL: URL(string: "https://concurred.ai/api/v1")!,
        extraHeaders: [:]
    )

    static let all: [Provider] = [.orcarouter, .openrouter, .featherless, .concurred]
}
