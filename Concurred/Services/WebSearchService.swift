import Foundation

struct WebSearchResult: Decodable, Sendable {
    let title: String
    let url: String
    let snippet: String?
}

/// The optional TinyFish CLI integration has a bounded lifetime and propagates failures.
enum WebSearchService {
    enum SearchError: LocalizedError {
        case unavailable, failed, timedOut, noResults
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Web search needs the TinyFish CLI in /opt/homebrew/bin or /usr/local/bin. Install it and sign in, or turn off Web search."
            case .failed: return "Web search failed. Check your TinyFish sign-in and connection, or turn off Web search."
            case .timedOut: return "Web search timed out. Try again, or turn off Web search."
            case .noResults: return "Web search found no usable results. Try a different question, or turn off Web search."
            }
        }
    }

    static func search(_ query: String) async throws -> [WebSearchResult] {
        guard let executable = ["/opt/homebrew/bin/tinyfish", "/usr/local/bin/tinyfish"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw SearchError.unavailable
        }
        let runner = SearchProcess(executable: executable, query: query)
        let data = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await runner.run()
        } onCancel: {
            runner.cancel(with: CancellationError())
        }
        try Task.checkCancellation()
        return try decodeResults(data)
    }

    static func decodeResults(_ data: Data) throws -> [WebSearchResult] {
        struct Response: Decodable { let results: [WebSearchResult] }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw SearchError.failed }
        let results = response.results.filter {
            guard let url = URL(string: $0.url) else { return false }
            return ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
        }
        guard !results.isEmpty else { throw SearchError.noResults }
        return Array(results.prefix(6))
    }
}

/// All Process lifecycle transitions are guarded by the lock; pipe reads run off the UI thread.
final class SearchProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var failure: Error?
    private var finished = false

    init(executable: String, query: String) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["search", "query", "--", query]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        environment.removeValue(forKey: "TINYFISH_DEBUG")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        // Avoid the undrained stderr pipe deadlock; do not expose CLI credentials in errors.
        process.standardError = FileHandle.nullDevice
    }

    func cancel(with error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        if failure == nil { failure = error }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    func run() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let timeout = DispatchWorkItem { self.cancel(with: WebSearchService.SearchError.timedOut) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
                defer { timeout.cancel() }
                let pipe = Pipe()
                self.process.standardOutput = pipe
                self.lock.lock()
                do {
                    if let error = self.failure { throw error }
                    try self.process.run()
                } catch {
                    self.finished = true
                    self.lock.unlock()
                    continuation.resume(throwing: error)
                    return
                }
                self.lock.unlock()
                var data = Data()
                while true {
                    let chunk = pipe.fileHandleForReading.readData(ofLength: 16_384)
                    if chunk.isEmpty { break }
                    if data.count + chunk.count > 2_097_152 {
                        self.cancel(with: WebSearchService.SearchError.failed)
                        break
                    }
                    data.append(chunk)
                }
                self.process.waitUntilExit()
                try? pipe.fileHandleForReading.close()
                self.lock.lock()
                self.finished = true
                let error = self.failure
                self.lock.unlock()
                if let error { continuation.resume(throwing: error) }
                else if self.process.terminationStatus != 0 {
                    continuation.resume(throwing: WebSearchService.SearchError.failed)
                } else { continuation.resume(returning: data) }
            }
        }
    }
}
