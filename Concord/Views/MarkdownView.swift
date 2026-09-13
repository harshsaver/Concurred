import AppKit
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

// MARK: - Rendering

struct MarkdownView: View {
    /// Code blocks larger than this are shown as a file card instead of inline.
    static let inlineCodeCharLimit = 1500
    static let inlineCodeLineLimit = 50
    /// Prose blocks larger than this render via NSTextView — SwiftUI `Text` spins on
    /// attribute/line-break enumeration for large attributed strings.
    static let inlineTextCharLimit = 2000
    /// Whole messages larger than this (by chars or block count) render via one native
    /// text view instead of many SwiftUI `Text`s, which don't scale.
    static let fastPathCharLimit = 6000
    static let fastPathBlockLimit = 40

    private let rawText: String
    private let blocks: [MarkdownBlock]
    private let onOpenFile: (CodeFile) -> Void

    init(text: String, onOpenFile: @escaping (CodeFile) -> Void = { _ in }) {
        let start = Date()
        let parsed = MarkdownParser.parse(text)
        rawText = text
        blocks = parsed
        self.onOpenFile = onOpenFile
        let fastPath = text.count > Self.fastPathCharLimit || parsed.count > Self.fastPathBlockLimit
        let ms = Date().timeIntervalSince(start) * 1000
        Log.render("markdown parse: \(text.count) chars → \(parsed.count) blocks fastPath=\(fastPath) in \(String(format: "%.1f", ms)) ms")
    }

    private var useFastPath: Bool {
        rawText.count > Self.fastPathCharLimit || blocks.count > Self.fastPathBlockLimit
    }

    var body: some View {
        if useFastPath {
            largeFallback
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(blocks) { block in
                    view(for: block)
                }
            }
        }
    }

    /// A plain, truncated preview for very long responses. Rendered with a single plain
    /// SwiftUI `Text` (no NSViewRepresentable, which loops inside a LazyVStack) — the full
    /// text opens in the side panel.
    private var largeFallback: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Label("Long response · \(rawText.count) chars", systemImage: "doc.plaintext")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onOpenFile(CodeFile(name: "response.md", language: "markdown", content: rawText))
                } label: {
                    Label("Open full response", systemImage: "arrow.up.right.square").font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private var preview: String {
        let limit = 2500
        return rawText.count > limit ? String(rawText.prefix(limit)) + "\n…" : rawText
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block.kind {
        case let .paragraph(text):
            if text.count > Self.inlineTextCharLimit {
                // Plain (single-run) text avoids the costly attributed-string metrics.
                Text(text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(inline(text))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .heading(level, text):
            Text(inline(text))
                .font(headingFont(level))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

        case let .code(code, language):
            if code.count > Self.inlineCodeCharLimit || lineCount(code) > Self.inlineCodeLineLimit {
                FileCardView(
                    file: CodeFile(name: suggestedFileName(language: language), language: language, content: code),
                    onOpen: onOpenFile
                )
            } else {
                CodeBlockView(code: code, language: language)
            }

        case let .bullet(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(inline(item)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case let .ordered(items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(offset + 1).").monospacedDigit().foregroundStyle(.secondary)
                        Text(inline(item)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case let .quote(text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(.secondary).frame(width: 3)
                Text(text.count > Self.inlineTextCharLimit ? AttributedString(text) : inline(text))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .rule:
            Divider()

        case let .image(alt, url):
            MarkdownImage(alt: alt, urlString: url)
        }
    }

    private func inline(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(string)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.bold)
        case 3: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }

    private func lineCount(_ string: String) -> Int {
        string.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }
}

struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty == false ? language! : "code").lowercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.quaternary)
        )
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            copied = false
        }
    }
}

struct MarkdownImage: View {
    let alt: String
    let urlString: String

    var body: some View {
        if let nsImage = dataImage {
            frame(Image(nsImage: nsImage))
        } else if let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                case let .success(image):
                    frame(image)
                case .failure:
                    fallback
                @unknown default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var dataImage: NSImage? {
        guard urlString.hasPrefix("data:"),
              let comma = urlString.firstIndex(of: ","),
              let data = Data(base64Encoded: String(urlString[urlString.index(after: comma)...]))
        else { return nil }
        return NSImage(data: data)
    }

    private func frame(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 440, maxHeight: 360, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.quaternary))
    }

    private var fallback: some View {
        Label(alt.isEmpty ? urlString : alt, systemImage: "photo")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
