import AppKit
import SwiftUI

@main
struct AIUsageMonitorApp: App {
    @State private var model = MenuBarViewModel(
        store: UsageStore(
            clients: [
                ClaudeClient(),
                CodexClient(),
                GeminiClient(),
                ZAIClient(),
                CerebrasClient(),
            ],
            pollIntervalSeconds: 60
        )
    )

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra(self.model.menuBarTitle, systemImage: self.model.menuBarSystemImage) {
            MenuBarRootView(model: self.model)
        }
        .menuBarExtraStyle(.window)
    }
}
