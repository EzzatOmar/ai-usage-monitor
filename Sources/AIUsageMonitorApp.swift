import AppKit
import SwiftUI

@MainActor
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
        Self.ejectDMGIfMounted()
    }

    private static func ejectDMGIfMounted() {
        let dmgVolume = URL(fileURLWithPath: "/Volumes/AIUsageMonitor")
        if FileManager.default.fileExists(atPath: dmgVolume.path) {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: dmgVolume)
        }
    }

    var body: some Scene {
        MenuBarExtra(self.model.menuBarTitle, systemImage: self.model.menuBarSystemImage) {
            MenuBarRootView(model: self.model)
        }
        .menuBarExtraStyle(.window)
    }
}
