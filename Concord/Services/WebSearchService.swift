import Foundation

struct WebSearchResult: Sendable {
    let title: String
    let url: String
    let snippet: String
}

/// Live web search via the locally-installed, already-authenticated TinyFish CLI.
/// Runs off the main thread and returns [] on any failure (grounding is best-effort).
enum WebSearchService {
    private static let candidates = [
        "/opt/homebrew/bin/tinyfish",
        "/usr/local/bin/tinyfish",
    ]

    static func search(_ query: String, limit: Int = 6) async -> [WebSearchResult] {
        await Task.detached(priority: .userInitiated) {
            guard let exe = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            else { return [] }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: exe)
            process.arguments = ["search", "query", query]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
            process.environment = env

            let out = Pipe()
            process.standardOutput = out
            process.standardError = Pipe()

            do { try process.run() } catch { return [] }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = object["results"] as? [[String: Any]]
            else { return [] }

            return results.prefix(limit).compactMap { item in
                guard let title = item["title"] as? String,
                      let url = item["url"] as? String
                else { return nil }
                return WebSearchResult(title: title, url: url, snippet: (item["snippet"] as? String) ?? "")
            }
        }.value
    }
}
