import AppKit
import SwiftUI

/// Native selection and clipboard behavior shared by the composer and bubbles.
class PlainCopyTextView: NSTextView {
    override func copy(_ sender: Any?) {
        copySelection(to: .general)
    }

    func copySelection(to pasteboard: NSPasteboard) {
        let range = selectedRange()
        guard range.length > 0 else { return }
        MessageClipboard.copy((string as NSString).substring(with: range), to: pasteboard)
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}

final class ComposerTextView: PlainCopyTextView {
    var onSend: () -> Void = {}
    var onFocus: (Bool) -> Void = { _ in }
    var focusWhenAttached = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if focusWhenAttached { window?.makeFirstResponder(self) }
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocus(true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocus(false) }
        return result
    }

    override func keyDown(with event: NSEvent) {
        if !handleReturn(event) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, event.modifierFlags.contains(.command), handleReturn(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleReturn(_ event: NSEvent) -> Bool {
        guard [36, 76].contains(event.keyCode), !hasMarkedText() else { return false }
        let modifiers = event.modifierFlags.intersection([.shift, .option, .command, .control])
        if modifiers.contains(.shift) || modifiers.contains(.option) || modifiers.contains(.control) {
            insertNewlineIgnoringFieldEditor(self)
        } else if !event.isARepeat {
            onSend()
        }
        return true
    }
}

struct MessageComposer: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let placeholder: String
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.focusRingType = .none
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = ComposerTextView()
        editor.focusRingType = .none
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 14)
        editor.textColor = .labelColor
        editor.textContainerInset = NSSize(width: 0, height: 5)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let editor = scroll.documentView as! ComposerTextView
        editor.onSend = onSend
        editor.onFocus = { value in
            DispatchQueue.main.async { if focused != value { focused = value } }
        }
        editor.focusWhenAttached = focused
        editor.setAccessibilityLabel(placeholder)
        if editor.string != text {
            editor.string = text
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            editor.scrollRangeToVisible(editor.selectedRange())
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let editor = nsView.documentView as! NSTextView
        editor.setFrameSize(NSSize(width: width, height: editor.frame.height))
        editor.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        let manager = editor.layoutManager!
        manager.ensureLayout(for: editor.textContainer!)
        let height = max(manager.usedRect(for: editor.textContainer!).height, manager.extraLineFragmentRect.maxY)
        return CGSize(width: width, height: min(130, max(28, ceil(height) + 10)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MessageComposer
        init(_ parent: MessageComposer) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

/// One native text view per visible row: selection spans paragraphs, lists and code.
struct SelectableMessageText: NSViewRepresentable {
    let content: NSAttributedString

    func makeNSView(context: Context) -> PlainCopyTextView {
        let view = PlainCopyTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: PlainCopyTextView, context: Context) {
        if view.textStorage?.isEqual(to: content) != true {
            let selection = view.selectedRange()
            view.textStorage?.setAttributedString(content)
            if NSMaxRange(selection) <= content.length { view.setSelectedRange(selection) }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PlainCopyTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let container = nsView.textContainer!
        container.containerSize = NSSize(width: max(1, width), height: .greatestFiniteMagnitude)
        nsView.layoutManager?.ensureLayout(for: container)
        let used = nsView.layoutManager!.usedRect(for: container)
        return CGSize(width: min(width, max(1, ceil(used.width))), height: max(18, ceil(used.height)))
    }
}
