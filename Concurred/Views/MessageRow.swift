import AppKit
import SwiftUI

struct MessageRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: ChatMessage
    var isLive = false
    var isSearching = false

    @State private var copied = false
    @State private var visibleLimit = 8000

    private static let streamingTailLimit = 8000
    private var isUser: Bool { message.role == .user }
    private var incomingFill: Color { colorScheme == .dark ? .white.opacity(0.09) : .black.opacity(0.055) }
    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 19, bottomLeadingRadius: isUser ? 19 : 5,
                               bottomTrailingRadius: isUser ? 5 : 19, topTrailingRadius: 19)
    }

    private var displayText: String {
        if isLive && message.text.count > Self.streamingTailLimit {
            return "…" + String(message.text.suffix(Self.streamingTailLimit))
        }
        return isLive ? message.text : String(message.text.prefix(visibleLimit))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 56) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                bubble
                if isLive && message.text.count > Self.streamingTailLimit {
                    Text("Showing the latest part. The full reply is kept.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else if !isLive && message.text.count > visibleLimit {
                    Button("Show more · \(message.text.count - visibleLimit) characters remaining") {
                        visibleLimit += 8000
                    }
                    .buttonStyle(.borderless).font(.caption)
                }
                if !message.text.isEmpty, !isLive {
                    HStack(spacing: 12) {
                        Button(action: copyMessage) {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .help(copied ? "Copied" : "Copy message")
                        if !isUser {
                            Button("Copy Markdown") { MessageClipboard.copy(message.text) }
                                .buttonStyle(.plain).help("Copy the original Markdown source")
                            CodeCopyMenu(text: message.text)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(height: 17)
                    .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: 640, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 56) }
        }
        .contextMenu {
            if !message.text.isEmpty {
                Button("Copy message", systemImage: "doc.on.doc", action: copyMessage)
                if !isUser {
                    Button("Copy Markdown") { MessageClipboard.copy(message.text) }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var bubble: some View {
        if message.text.isEmpty && !isUser {
            HStack(spacing: 10) {
                TypingIndicator()
                if isSearching {
                    Text("Searching the web").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(incomingFill, in: bubbleShape)
        } else {
            SelectableMessageText(content: renderedText)
                .padding(.horizontal, 15).padding(.vertical, isUser ? 10 : 12)
                .background(isUser ? Color(red: 0, green: 0.42, blue: 0.9) : incomingFill, in: bubbleShape)
        }
    }

    private var renderedText: NSAttributedString {
        if !isUser && !isLive { return messageMarkdown(displayText) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return NSAttributedString(string: displayText, attributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: isUser ? NSColor.white : NSColor.labelColor,
            .paragraphStyle: paragraph
        ])
    }

    private func copyMessage() {
        MessageClipboard.copy(MessageClipboard.text(for: message))
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            copied = false
        }
    }
}

private struct CodeCopyMenu: View {
    let text: String
    private var blocks: [(String, String?)] {
        MarkdownParser.parse(text).compactMap {
            if case let .code(code, language) = $0.kind { return (code, language) }
            return nil
        }
    }
    var body: some View {
        if !blocks.isEmpty {
            Menu {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    Button("Block \(index + 1)\(block.1.map { " · " + $0 } ?? "")") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(block.0, forType: .string)
                    }
                }
            } label: {
                Label("Copy code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Copy a code block")
        }
    }
}
