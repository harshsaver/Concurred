import SwiftUI

/// A model-routing provider the app can talk to.
enum ProviderStatus: Equatable {
    case available   // fully wired up in this version
    case closed      // card is shown, but integration lands in a later version
}

struct Provider: Identifiable, Hashable {
    let id: String
    let name: String
    let tagline: String
    let symbol: String       // SF Symbol
    let tint: Color
    let status: ProviderStatus
    let docsURL: URL
    let apiKeysURL: URL?
    let keyPlaceholder: String

    // API config (populated for integrated providers; `baseURL` is nil when closed).
    let baseURL: URL?
    let fallbackModels: [String]
    let extraHeaders: [String: String]

    static func == (lhs: Provider, rhs: Provider) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Provider {
    static let orcarouter = Provider(
        id: "orcarouter",
        name: "OrcaRouter",
        tagline: "One API for every model. Zero markup.",
        symbol: "fish.fill",
        tint: Color(red: 0.10, green: 0.55, blue: 0.72),
        status: .available,
        docsURL: URL(string: "https://docs.orcarouter.ai")!,
        apiKeysURL: URL(string: "https://www.orcarouter.ai")!,
        keyPlaceholder: "sk-orca-…",
        baseURL: URL(string: "https://api.orcarouter.ai/v1"),
        fallbackModels: [
            "openai/gpt-4o-mini",
            "openai/gpt-5",
            "anthropic/claude-sonnet-4.6",
            "google/gemini-2.5-flash",
            "deepseek/deepseek-chat",
        ],
        extraHeaders: [:]
    )

    static let openrouter = Provider(
        id: "openrouter",
        name: "OpenRouter",
        tagline: "A unified interface for LLMs.",
        symbol: "arrow.triangle.branch",
        tint: Color(red: 0.37, green: 0.35, blue: 0.85),
        status: .available,
        docsURL: URL(string: "https://openrouter.ai/docs")!,
        apiKeysURL: URL(string: "https://openrouter.ai/keys")!,
        keyPlaceholder: "sk-or-…",
        baseURL: URL(string: "https://openrouter.ai/api/v1"),
        fallbackModels: [
            "openai/gpt-4o-mini",
            "anthropic/claude-3.5-sonnet",
            "google/gemini-2.0-flash-001",
            "meta-llama/llama-3.3-70b-instruct",
            "deepseek/deepseek-chat",
        ],
        extraHeaders: [
            "HTTP-Referer": "https://october.dev",
            "X-Title": "Concord",
        ]
    )

    static let featherless = Provider(
        id: "featherless",
        name: "Featherless",
        tagline: "Serverless inference for open models.",
        symbol: "wind",
        tint: Color(red: 0.91, green: 0.42, blue: 0.56),
        status: .available,
        docsURL: URL(string: "https://featherless.ai/docs")!,
        apiKeysURL: URL(string: "https://featherless.ai")!,
        keyPlaceholder: "rc_…",
        baseURL: URL(string: "https://api.featherless.ai/v1"),
        fallbackModels: [
            "meta-llama/Meta-Llama-3.1-8B-Instruct",
            "Qwen/Qwen2.5-72B-Instruct",
            "mistralai/Mistral-Nemo-Instruct-2407",
        ],
        extraHeaders: [:]
    )

    static let concurred = Provider(
        id: "concurred",
        name: "Concurred",
        tagline: "One key, 9 models — consensus routing.",
        symbol: "checkmark.seal.fill",
        tint: Color(red: 0.20, green: 0.66, blue: 0.44),
        status: .available,
        docsURL: URL(string: "https://concurred.ai/docs/api")!,
        apiKeysURL: URL(string: "https://concurred.ai/dashboard")!,
        keyPlaceholder: "ck_…",
        baseURL: URL(string: "https://concurred.ai/api/v1"),
        fallbackModels: [
            "auto",
            "gpt",
            "claude",
            "grok",
            "gemini",
            "deepseek",
            "kimi",
            "mistral",
            "llama",
            "minimax",
        ],
        extraHeaders: [:]
    )

    static let all: [Provider] = [.orcarouter, .openrouter, .featherless, .concurred]
}
