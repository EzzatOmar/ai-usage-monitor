import AppKit
import SwiftUI

@MainActor
@main
struct AIUsageMonitorApp: App {
    @State private var model: MenuBarViewModel
    @State private var settingsWindowPresenter: SettingsWindowPresenter

    init() {
        let openAIAccounts = OpenAIAccountStore.loadAccounts()
        let model = MenuBarViewModel(
            store: UsageStore(
                clients: [
                    ClaudeClient(),
                    GeminiClient(),
                    ZAIClient(),
                    CerebrasClient(),
                    KimiClient(),
                    MinimaxClient(),
                    QwenCloudClient(),
                    CursorClient(),
                ],
                dynamicClients: {
                    OpenAIAccountStore.loadAccounts()
                        .filter(\.isEnabled)
                        .map { CodexClient(account: $0) }
                },
                pollIntervalSeconds: 300
            ),
            openAIAccounts: openAIAccounts
        )
        self._model = State(initialValue: model)
        self._settingsWindowPresenter = State(
            initialValue: SettingsWindowPresenter(model: model)
        )

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
            MenuBarRootView(
                model: self.model,
                onOpenSettings: { self.settingsWindowPresenter.showSettings() }
            )
        }
        .menuBarExtraStyle(.window)
    }
}
