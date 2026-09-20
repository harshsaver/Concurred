import AppKit
import SwiftUI
import XCTest
@testable import Concurred

/// Deterministic native render checks use mock credentials and temporary chat storage.
@MainActor
final class ViewRenderingTests: XCTestCase {
    func testHomeAndSettingsRenderAtSupportedSizes() throws {
        let appStore = AppStore(secrets: MemorySecrets())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ConcurredViewTests-\(UUID())/chats.json")
        let conversations = ConversationStore(fileURL: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try render(ContentView().environment(appStore).environment(conversations), name: "home", width: 820, height: 560)
        try render(ContentView().environment(appStore).environment(conversations), name: "home-dark", width: 1200, height: 800, dark: true)
        try render(ContentView().environment(appStore).environment(conversations), name: "home-wide", width: 1500, height: 940, dark: true)
        try render(SettingsForm().environment(appStore), name: "settings", width: 560, height: 540)
    }

    func testLongMarkdownAndCodeRenderWithoutTruncatingStoredMessage() throws {
        let message = ChatMessage(role: .assistant, text: "# A useful reply\n\n7. First item\n8. Second item\n\n```swift\nlet greeting = \"Hello\"\nprint(greeting)\n```\n\n" + String(repeating: "A longer paragraph of response text. ", count: 300))
        try render(ScrollView { MessageRow(message: message).padding(20) }, name: "message", width: 550, height: 600)
        XCTAssertGreaterThan(message.text.count, 8000)
    }

    func testChatComposerRendersAtMinimumWidth() throws {
        let secrets = MemorySecrets()
        let appStore = AppStore(secrets: secrets)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ConcurredViewTests-\(UUID())/chats.json")
        let store = ConversationStore(fileURL: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var chat = store.newOrReuseEmpty(providerID: "openrouter", model: "example/model")
        chat.title = "A weekend in Kyoto"
        chat.messages = [ChatMessage(role: .user, text: "I have two days in Kyoto. Where should I start?"),
                         ChatMessage(role: .assistant, text: "Start slowly in Higashiyama. Walk the lanes around Ninenzaka before the crowds, then stop for tea.\n\nOn your second day, head to Arashiyama early and leave the afternoon open to explore."),
                         ChatMessage(role: .user, text: "That sounds good. Any quiet spots for coffee?")]
        store.save(chat)
        for title in ["Ideas for the living room", "Learning a little Swift", "A better morning routine"] {
            var other = store.newOrReuseEmpty(providerID: "openrouter", model: "example/model")
            other.title = title
            other.messages = [ChatMessage(role: .assistant, text: "Let's make a simple plan you can come back to.")]
            store.save(other)
        }
        store.save(chat)
        let vm = ChatViewModel(provider: .openrouter, apiKey: "test-key", conversationID: chat.id, store: store, client: RenderChatClient())
        vm.input = "Somewhere with a view would be lovely"
        let workspace = HStack(spacing: 0) {
            ConversationSidebar(provider: .openrouter, selection: .constant(chat.id)).frame(width: 280)
            Divider()
            ChatDetail(viewModel: vm, apiKey: "test-key").frame(minWidth: 480)
        }.environment(appStore).environment(store)
        try render(workspace, name: "chat-light", width: 820, height: 560)
        try render(workspace, name: "chat-dark", width: 1000, height: 700, dark: true)
        try render(workspace, name: "chat-wide", width: 1440, height: 900, dark: true)

    }

    func testEmptyConversationRendersAtMinimumAndWideSizes() throws {
        let appStore = AppStore(secrets: MemorySecrets())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ConcurredViewTests-\(UUID())/chats.json")
        let store = ConversationStore(fileURL: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let chat = store.newOrReuseEmpty(providerID: "openrouter", model: "anthropic/claude-sonnet-4.5")
        let vm = ChatViewModel(provider: .openrouter, apiKey: "test-key", conversationID: chat.id, store: store, client: RenderChatClient())
        let detail = ChatDetail(viewModel: vm, apiKey: "test-key")
            .environment(appStore).environment(store)
        try render(detail, name: "empty-minimum", width: 480, height: 560)
        let workspace = HStack(spacing: 0) {
            ConversationSidebar(provider: .openrouter, selection: .constant(chat.id)).frame(width: 260)
            Divider()
            detail
        }.environment(appStore).environment(store)
        try render(workspace, name: "empty-wide", width: 1440, height: 900, dark: true)
        XCTAssertTrue(vm.messages.isEmpty)
    }

    func testCloakReviewAndMultilineComposerRender() throws {
        let review = CloakReview(original: [WireMessage(role: "user", content: "Clara Barton owns 60%. Contact clara@example.org.")], identity: .empty, vault: .init())
        try render(CloakReviewSheet(review: review, usesSearch: true, onSend: { _ in }), name: "cloak-review", width: 700, height: 650)
        let appStore = AppStore(secrets: MemorySecrets())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ConcurredViewTests-\(UUID())/chats.json")
        let store = ConversationStore(fileURL: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let chat = store.newOrReuseEmpty(providerID: "openrouter", model: "example/model")
        let vm = ChatViewModel(provider: .openrouter, apiKey: "test-key", conversationID: chat.id, store: store, client: RenderChatClient())
        vm.cloak = true
        vm.input = "First line\nSecond line\nThird line\nFourth line\nFifth line\nSixth line\nSeventh line\nEighth line"
        try render(ChatDetail(viewModel: vm, apiKey: "test-key").environment(appStore).environment(store),
                   name: "multiline-cloak-composer", width: 480, height: 560)
    }

    func testAltIDPortraitStatesRenderWithoutLoadingAnIdentity() throws {
        try render(AltIDHeader(cloakEnabled: .constant(false)).padding(20), name: "alt-id-off", width: 360, height: 135, dark: true)
        try render(AltIDHeader(cloakEnabled: .constant(true)).padding(20), name: "alt-id-on", width: 360, height: 135, dark: true)
        let networkStates = [NetworkSettings(), NetworkSettings(userAgent: "CustomAgent/1.0"),
                             NetworkSettings(proxyEnabled: true, proxyIsSOCKS: true, proxyHost: "127.0.0.1", proxyPort: 9050)]
        for (index, settings) in networkStates.enumerated() {
            try render(NetworkHeader(settings: settings, hasChanges: index > 0)
                .transaction { $0.disablesAnimations = true }.padding(20),
                       name: "network-header-\(index)", width: 320, height: 155, dark: true)
        }
        for (index, preset) in UserAgentPreset.all.enumerated() {
            try render(UserAgentPreview(preset: preset, pulse: 0).padding(16),
                       name: "user-agent-\(index)", width: 280, height: 245, dark: true)
        }
        try render(DeviceSignalScene(device: .android, progress: 0.5).padding(12),
                   name: "android-signal", width: 280, height: 175, dark: true)
        try render(DeviceSignalScene(device: .windows, progress: 0.5).padding(12),
                   name: "windows-signal", width: 280, height: 175, dark: false)
    }

    private func render<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat, dark: Bool = false) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 1000)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("concord-audit-screenshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        window.contentView = nil
    }
}

private struct RenderChatClient: ChatServing {
    func listModels() async throws -> [String] { ["example/model"] }
    func chatStream(model: String, messages: [WireMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
