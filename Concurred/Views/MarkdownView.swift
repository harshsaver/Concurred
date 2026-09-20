import AppKit
import SwiftUI

// MARK: - Block model & parser

struct MarkdownBlock {
    enum Kind {
        case paragraph(String)
        case heading(Int, String)
        case code(String, String?)   // code, language
        case bullet([String])
        case ordered(Int, [String])
        case quote(String)
        case rule
        case image(alt: String, url: String)
    }

    let kind: Kind
}

/// A small, dependency-free Markdown block parser covering the elements chat models
/// commonly emit: paragraphs, fenced code, headings, lists, quotes, rules, images.
enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
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

            let fence = trimmed.prefix { $0 == trimmed.first }
            if let marker = trimmed.first, (marker == "`" || marker == "~"), fence.count >= 3 {
                flushParagraph()
                let language = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.count >= fence.count && candidate.allSatisfy({ $0 == marker }) { break }
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
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
                let start = Int(trimmed.prefix(drop - 2)) ?? 1
                var items: [String] = []
                while index < lines.count,
                      let count = orderedPrefix(lines[index].trimmingCharacters(in: .whitespaces)) {
                    let item = lines[index].trimmingCharacters(in: .whitespaces).dropFirst(count)
                    items.append(String(item))
                    index += 1
                }
                blocks.append(MarkdownBlock(kind: .ordered(start, items)))
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

// MARK: - Native attributed text and plain clipboard content

func attributedMarkdown(_ text: String) -> AttributedString {
    AttributedString(messageMarkdown(text))
}

func messageMarkdown(_ text: String, includeCodeLabels: Bool = true) -> NSAttributedString {
    let output = NSMutableAttributedString()
    let baseFont = NSFont.systemFont(ofSize: 14)
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 4

    func inline(_ text: String) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: text, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible))) ?? AttributedString(text)
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let value = String(parsed[run.range].characters)
            var attributes: [NSAttributedString.Key: Any] = [.font: baseFont, .foregroundColor: NSColor.labelColor]
            let intent = run.inlinePresentationIntent ?? []
            var font = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) : baseFont
            if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            attributes[.font] = font
            if intent.contains(.code) { attributes[.backgroundColor] = NSColor.quaternaryLabelColor }
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link, ["http", "https", "mailto"].contains(link.scheme?.lowercased() ?? "") {
                attributes[.link] = link
            }
            result.append(NSAttributedString(string: value, attributes: attributes))
        }
        return result
    }

    func append(_ value: String, attributes: [NSAttributedString.Key: Any] = [:]) {
        output.append(NSAttributedString(string: value, attributes: attributes))
    }

    for block in MarkdownParser.parse(text) {
        if output.length > 0 { append("\n\n") }
        switch block.kind {
        case let .paragraph(text): output.append(inline(text))
        case let .heading(level, text):
            let heading = NSMutableAttributedString(attributedString: inline(text))
            heading.addAttribute(.font, value: NSFont.systemFont(ofSize: level == 1 ? 22 : (level == 2 ? 19 : 16), weight: .bold), range: NSRange(location: 0, length: heading.length))
            output.append(heading)
        case let .code(code, language):
            if includeCodeLabels, let language, !language.isEmpty {
                append(language.lowercased() + "\n", attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
            }
            append(code, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .backgroundColor: NSColor.quaternaryLabelColor])
        case let .bullet(items):
            for (index, item) in items.enumerated() {
                if index > 0 { append("\n") }
                append("•  ")
                output.append(inline(item))
            }
        case let .ordered(start, items):
            for (index, item) in items.enumerated() {
                if index > 0 { append("\n") }
                append("\(start + index).  ")
                output.append(inline(item))
            }
        case let .quote(text): output.append(inline(text))
        case .rule: append("──────────")
        case let .image(alt, url):
            let label = alt.isEmpty ? url : alt
            if let link = URL(string: url), ["http", "https"].contains(link.scheme?.lowercased() ?? "") {
                append(label, attributes: [.link: link])
            } else { append(label) }
        }
    }
    let range = NSRange(location: 0, length: output.length)
    output.addAttribute(.paragraphStyle, value: paragraph, range: range)
    output.enumerateAttributes(in: range) { attributes, range, _ in
        if attributes[.font] == nil { output.addAttribute(.font, value: baseFont, range: range) }
        if attributes[.foregroundColor] == nil { output.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range) }
    }
    return output
}

enum MessageClipboard {
    static func text(for message: ChatMessage, markdown: Bool = false) -> String {
        if message.role == .user || markdown { return message.text }
        return messageMarkdown(message.text, includeCodeLabels: false).string
    }

    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
