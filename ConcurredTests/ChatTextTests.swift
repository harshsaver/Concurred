import AppKit
import XCTest
@testable import Concurred

@MainActor
final class ChatTextTests: XCTestCase {
    private func enter(_ modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                        windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                        isARepeat: repeatKey, keyCode: 36)!
    }

    func testModifiedReturnInsertsNewlineAtCursorWithoutSending() {
        let view = ComposerTextView()
        var sends = 0
        view.onSend = { sends += 1 }
        for modifiers: NSEvent.ModifierFlags in [.shift, [.command, .shift], .option, [.shift, .capsLock]] {
            view.string = "first second"
            view.setSelectedRange(NSRange(location: 5, length: 1))
            view.keyDown(with: enter(modifiers))
            XCTAssertEqual(view.string, "first\nsecond")
        }
        XCTAssertEqual(sends, 0)
        view.keyDown(with: enter())
        view.keyDown(with: enter(.command))
        XCTAssertEqual(sends, 2)
        view.keyDown(with: enter([], repeatKey: true))
        XCTAssertEqual(sends, 2)
    }

    func testCommandShiftReturnIsHandledBeforeWindowShortcuts() {
        let view = ComposerTextView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeFirstResponder(view)
        var sends = 0
        view.onSend = { sends += 1 }
        view.string = "hello"
        view.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertTrue(view.performKeyEquivalent(with: enter([.command, .shift])))
        XCTAssertEqual(view.string, "hello\n")
        XCTAssertEqual(sends, 0)
        window.contentView = nil
    }

    func testReturnWhileComposingAnInputMethodDoesNotSend() {
        let view = ComposerTextView()
        var sends = 0
        view.onSend = { sends += 1 }
        view.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(view.hasMarkedText())
        view.keyDown(with: enter())
        XCTAssertEqual(sends, 0)
    }

    func testSelectionCopiesOnlySelectedContentAsPlainText() {
        let view = PlainCopyTextView()
        view.textStorage?.setAttributedString(messageMarkdown("First **paragraph**.\n\n7. Seven\n8. Eight\n\n```swift\nlet x = 1\n```"))
        let substring = "paragraph.\n\n7.  Seven\n8.  Eight"
        view.setSelectedRange((view.string as NSString).range(of: substring))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        view.copySelection(to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), substring)
        XCTAssertNil(pasteboard.data(forType: .rtf))
        XCTAssertNil(pasteboard.data(forType: .html))
    }

    func testWholeMessageCopyHasNoMarkdownOrCodeLanguageLabel() {
        let source = "# Title\n\n**Hello** `world`.\n\n```swift\nlet value = 60\nprint(value)\n```"
        let message = ChatMessage(role: .assistant, text: source)
        XCTAssertEqual(MessageClipboard.text(for: message), "Title\n\nHello world.\n\nlet value = 60\nprint(value)")
        XCTAssertEqual(MessageClipboard.text(for: message, markdown: true), source)
        XCTAssertEqual(MessageClipboard.text(for: ChatMessage(role: .user, text: source)), source)
    }

    func testPastedMultilineContentNeverSubmits() {
        let view = ComposerTextView()
        view.isRichText = false
        var sends = 0
        view.onSend = { sends += 1 }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let content = "Hello 👋\n\n    indented\n60% share\n"
        pasteboard.setString(content, forType: .string)
        XCTAssertTrue(view.readSelection(from: pasteboard, type: .string))
        XCTAssertEqual(view.string, content)
        XCTAssertEqual(sends, 0)
    }
}
