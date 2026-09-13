import Foundation
import OSLog

/// Logs to both the unified log and a plain text file that is always easy to read:
///   ~/Library/Application Support/dev.october.concord/concord.log
///
/// Unified log (if it surfaces): log stream --predicate 'subsystem == "dev.october.concord"'
enum Log {
    private static let subsystem = "dev.october.concord"
    private static let osChat = Logger(subsystem: subsystem, category: "chat")
    private static let osRender = Logger(subsystem: subsystem, category: "render")

    static func chat(_ message: String) {
        osChat.notice("\(message, privacy: .public)")
        append("chat", message)
    }

    static func render(_ message: String) {
        osRender.notice("\(message, privacy: .public)")
        append("render", message)
    }

    static func error(_ message: String) {
        osChat.error("\(message, privacy: .public)")
        append("error", message)
    }

    // MARK: - File sink

    private static let fileURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent(subsystem, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("concord.log")
    }()

    private static let queue = DispatchQueue(label: "\(subsystem).log")
    private static let formatter = ISO8601DateFormatter()

    private static func append(_ category: String, _ message: String) {
        let now = Date()
        queue.async {
            let line = "\(formatter.string(from: now)) [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
