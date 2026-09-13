import AppKit
import SwiftUI

/// A large chunk of content (usually a code block) shown as a card and opened in a panel.
struct CodeFile: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let language: String?
    let content: String

    var subtitle: String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).count
        let kb = Double(content.utf8.count) / 1024
        var parts: [String] = []
        if let language, !language.isEmpty { parts.append(language) }
        parts.append("\(lines) lines")
        parts.append(String(format: "%.1f KB", kb))
        return parts.joined(separator: " · ")
    }
}

/// Maps a fenced-code language to a plausible filename.
func suggestedFileName(language: String?) -> String {
    let ext: String
    switch (language ?? "").lowercased() {
    case "python", "py": ext = "py"
    case "swift": ext = "swift"
    case "javascript", "js": ext = "js"
    case "typescript", "ts": ext = "ts"
    case "tsx": ext = "tsx"
    case "jsx": ext = "jsx"
    case "json": ext = "json"
    case "bash", "sh", "shell", "zsh": ext = "sh"
    case "html": ext = "html"
    case "css": ext = "css"
    case "go": ext = "go"
    case "rust", "rs": ext = "rs"
    case "c": ext = "c"
    case "cpp", "c++", "cxx": ext = "cpp"
    case "java": ext = "java"
    case "kotlin", "kt": ext = "kt"
    case "ruby", "rb": ext = "rb"
    case "php": ext = "php"
    case "yaml", "yml": ext = "yml"
    case "toml": ext = "toml"
    case "sql": ext = "sql"
    case "markdown", "md": ext = "md"
    case "xml": ext = "xml"
    case "": ext = "txt"
    default: ext = "txt"
    }
    return "snippet.\(ext)"
}

/// Compact card standing in for a large block; tap to open it in the panel.
struct FileCardView: View {
    let file: CodeFile
    let onOpen: (CodeFile) -> Void

    var body: some View {
        Button {
            onOpen(file)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.subheadline.weight(.medium))
                    Text(file.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: 420, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.quaternary)
            )
        }
        .buttonStyle(.plain)
    }
}

/// The panel body: header + a native text view that handles very large content well.
struct FileDetailView: View {
    let file: CodeFile
    var onClose: () -> Void = {}
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name).font(.headline)
                    Text(file.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Button(action: save) {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }
            }
            .padding(10)
            Divider()
            CodeTextView(text: file.content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(file.content, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            copied = false
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.name
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? file.content.data(using: .utf8)?.write(to: url)
        }
    }
}

/// Read-only, selectable, word-wrapping text backed by NSTextView, for large prose
/// blocks that would make SwiftUI `Text` spin on attribute/line-break enumeration.
struct WrappingTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }
}

/// Read-only, selectable, non-wrapping monospaced text backed by NSTextView.
/// NSTextView handles large documents far better than SwiftUI `Text`.
struct CodeTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }
}
