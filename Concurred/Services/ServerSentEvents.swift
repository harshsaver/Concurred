import Foundation

/// Incremental UTF-8 SSE framing, including CR/LF, comments and multiline data fields.
/// Parsing bytes directly preserves empty lines (AsyncBytes.lines omits them).
/// Event framing: https://html.spec.whatwg.org/multipage/server-sent-events.html#parsing-an-event-stream
struct ServerSentEvents {
    private var line: [UInt8] = []
    private var dataLines: [String] = []
    private var dataSize = 0
    private var afterCR = false
    private var isFirstLine = true
    private let maxEventBytes = 1_048_576

    mutating func append(_ byte: UInt8) throws -> String? {
        if afterCR {
            afterCR = false
            if byte == 10 { return nil }
        }
        if byte == 13 || byte == 10 {
            afterCR = byte == 13
            return try finishLine()
        }
        line.append(byte)
        guard line.count + dataSize <= maxEventBytes else { throw ChatClient.ClientError.invalidResponse }
        return nil
    }

    private mutating func finishLine() throws -> String? {
        guard var value = String(bytes: line, encoding: .utf8) else { throw ChatClient.ClientError.invalidResponse }
        line.removeAll(keepingCapacity: true)
        if isFirstLine {
            isFirstLine = false
            if value.hasPrefix("\u{FEFF}") { value.removeFirst() }
        }
        if value.isEmpty {
            defer { dataLines.removeAll(keepingCapacity: true); dataSize = 0 }
            return dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
        }
        if value == "data" { dataLines.append(""); dataSize += 1 }
        else if value.hasPrefix("data:") {
            var data = String(value.dropFirst(5))
            if data.hasPrefix(" ") { data.removeFirst() }
            dataSize += data.utf8.count + 1
            dataLines.append(data)
        }
        guard dataSize <= maxEventBytes else { throw ChatClient.ClientError.invalidResponse }
        return nil
    }
}
