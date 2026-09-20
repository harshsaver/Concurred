import SwiftUI

@main
struct ConcurredApp: App {
    @State private var store = AppStore()
    @State private var conversations = ConversationStore()

    var body: some Scene {
        Window("Concurred", id: "main") {
            ContentView()
                .environment(store)
                .environment(conversations)
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 920, height: 680)

        Settings {
            SettingsForm()
                .environment(store)
                .frame(width: 560, height: 540)
        }
    }
}
