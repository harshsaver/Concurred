import SwiftUI

// MARK: - Block model & parser

struct MarkdownBlock: Identifiable {
    enum Kind {
        case paragraph(String)
        case heading(Int, String)
        case code(String, String?)   // code, language
        case bullet([String])
        case ordered([String])
        case quote(String)
        case rule
        case image(alt: String, url: String)
    }

    let id = UUID()
    let kind: Kind
}

/// A small, dependency-free Markdown block parser covering the elements chat models
/// commonly emit: paragraphs, fenced code, headings, lists, quotes, rules, images.
enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var index = 0
        var paragraph: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(MarkdownBlock(kind: .paragraph(joined))) }
            paragraph.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                index += 1 // skip closing fence
                blocks.append(MarkdownBlock(kind: .code(code.joined(separator: "\n"),
                                                        language.isEmpty ? nil : language)))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let image = parseImage(trimmed) {
                flushParagraph()
                blocks.append(MarkdownBlock(kind: .image(alt: image.0, url: image.1)))
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(MarkdownBlock(kind: .rule))
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(MarkdownBlock(kind: .heading(heading.0, heading.1)))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while index < lines.count,
                      lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let stripped = lines[index].trimmingCharacters(in: .whitespaces).dropFirst()
                    quote.append(stripped.trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(MarkdownBlock(kind: .quote(quote.joined(separator: "\n"))))
                continue
            }

            if isBullet(trimmed) {
                flushParagraph()
                var items: [String] = []
                while index < lines.count, isBullet(lines[index].trimmingCharacters(in: .whitespaces)) {
                    let item = lines[index].trimmingCharacters(in: .whitespaces).dropFirst(2)
                    items.append(String(item))
                    index += 1
                }
                blocks.append(MarkdownBlock(kind: .bullet(items)))
                continue
            }

            if let drop = orderedPrefix(trimmed) {
                flushParagraph()
                var items: [String] = []
                while index < lines.count,
                      let count = orderedPrefix(lines[index].trimmingCharacters(in: .whitespaces)) {
                    let item = lines[index].trimmingCharacters(in: .whitespaces).dropFirst(count)
                    items.append(String(item))
                    index += 1
                }
                _ = drop
                blocks.append(MarkdownBlock(kind: .ordered(items)))
                continue
            }

            paragraph.append(line)
            index += 1
        }
        flushParagraph()
        return blocks
    }

    private static func parseHeading(_ line: String) -> (Int, String)? {
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6, line.count > level else { return nil }
        guard line[line.index(line.startIndex, offsetBy: level)] == " " else { return nil }
        return (level, String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces))
    }

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    /// Returns the number of leading characters to drop for an ordered-list marker ("12. ").
    private static func orderedPrefix(_ line: String) -> Int? {
        var index = line.startIndex
        var digits = 0
        while index < line.endIndex, line[index].isNumber {
            index = line.index(after: index)
            digits += 1
        }
        guard digits > 0, index < line.endIndex, line[index] == "." else { return nil }
        let afterDot = line.index(after: index)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return digits + 2
    }

    private static func parseImage(_ line: String) -> (String, String)? {
        guard line.hasPrefix("!["), let close = line.firstIndex(of: "]") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2) ..< close])
        let rest = line[line.index(after: close)...]
        guard rest.hasPrefix("("), rest.hasSuffix(")") else { return nil }
        return (alt, String(rest.dropFirst().dropLast()))
    }
}

// MARK: - Single-AttributedString renderer

/// Renders lightweight Markdown into ONE `AttributedString`, so a message is a single
/// cheap `Text` — never many attributed Text views. This is the core of the hang fix:
/// no per-block SwiftUI views, no materials, no NSViewRepresentables, no selection
/// overlays in the scrolling `List`.
func attributedMarkdown(_ text: String) -> AttributedString {
    var out = AttributedString()

    let codeBackground = Color.gray.opacity(0.18)

    func inline(_ string: String) -> AttributedString {
        var a = (try? AttributedString(
            markdown: string,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(string)
        // Style inline `code` spans: monospaced on a subtle background.
        for run in a.runs where run.inlinePresentationIntent?.contains(.code) == true {
            a[run.range].font = .system(.body, design: .monospaced)
            a[run.range].backgroundColor = codeBackground
        }
        return a
    }

    func gap() {
        if !out.characters.isEmpty { out += AttributedString("\n\n") }
    }

    for block in MarkdownParser.parse(text) {
        switch block.kind {
        case let .paragraph(t):
            gap()
            out += inline(t)

        case let .heading(level, t):
            gap()
            var h = inline(t)
            let size: CGFloat = level <= 1 ? 22 : (level == 2 ? 19 : 16)
            h.font = .system(size: size, weight: .bold)
            out += h

        case let .code(code, language):
            gap()
            if let language, !language.isEmpty {
                var caption = AttributedString(language.lowercased())
                caption.font = .caption2.weight(.semibold)
                caption.foregroundColor = .secondary
                out += caption
                out += AttributedString("\n")
            }
            var c = AttributedString(code)
            c.font = .system(.callout, design: .monospaced)
            c.backgroundColor = codeBackground
            out += c

        case let .bullet(items):
            gap()
            for (i, item) in items.enumerated() {
                if i > 0 { out += AttributedString("\n") }
                out += AttributedString("•  ")
                out += inline(item)
            }

        case let .ordered(items):
            gap()
            for (i, item) in items.enumerated() {
                if i > 0 { out += AttributedString("\n") }
                out += AttributedString("\(i + 1).  ")
                out += inline(item)
            }

        case let .quote(t):
            gap()
            var q = inline(t)
            q.foregroundColor = .secondary
            out += q

        case .rule:
            gap()
            var r = AttributedString("──────────")
            r.foregroundColor = .secondary
            out += r

        case let .image(alt, url):
            gap()
            var img = AttributedString("🖼  " + (alt.isEmpty ? url : alt))
            img.foregroundColor = .accentColor
            if let link = URL(string: url) { img.link = link }
            out += img
        }
    }

    return out
}
