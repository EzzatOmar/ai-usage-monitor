import AppKit
import SwiftUI

/// Standalone real-MenuBarExtra smoke test; compiled with production Sources except the app entry point.
@MainActor
final class MenuSizingSmokeDelegate: NSObject, NSApplicationDelegate {
    static let model = MenuBarViewModel(
        store: UsageStore(clients: [], pollIntervalSeconds: 3600),
        openAIAccounts: [.defaultAccount(isEnabled: false)]
    )
    static let settings = SettingsWindowPresenter(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                try await self.verifyMenu()
                print("Menu window sizing smoke passed.")
                NSApp.terminate(nil)
            } catch {
                fputs("Menu window sizing smoke failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    private func verifyMenu() async throws {
        NSApp.setActivationPolicy(.accessory)
        let model = Self.model
        let keys = ProviderID.allCases.map { "aiUsageMonitor.providerEnabled.\($0.rawValue)" }
            + ["aiUsageMonitor.openAIAccounts.v1"]
        let saved = keys.map { (key: $0, value: UserDefaults.standard.object(forKey: $0)) }
        defer {
            Self.settings.closeSettings()
            for entry in saved {
                if let value = entry.value { UserDefaults.standard.set(value, forKey: entry.key) }
                else { UserDefaults.standard.removeObject(forKey: entry.key) }
            }
        }

        let providers: [ProviderID] = [.claude, .gemini, .zai, .kimi, .openCodeGo]
        model.providerEnabled = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map {
            ($0, providers.contains($0))
        })
        try await Task.sleep(for: .milliseconds(200))
        guard let button = NSApp.windows.compactMap({ self.statusButton(in: $0.contentView) }).first else {
            throw SmokeFailure(message: "No status button")
        }
        button.performClick(nil)
        try await Task.sleep(for: .milliseconds(200))
        guard let window = NSApp.windows.first(where: { self.containsSizingBridge($0.contentView) }) else {
            throw SmokeFailure(message: "No menu window")
        }
        try await self.assertFits(window, step: "five providers")

        // Use the same presenter and mutation methods as the real Settings toggles.
        button.performClick(nil)
        Self.settings.showSettings()
        model.setProviderEnabled(.kimi, false)
        button.performClick(nil)
        try await self.assertFits(window, step: "Settings off, then reopen")

        for provider in ProviderID.allCases where provider != .codex {
            model.setProviderEnabled(provider, true)
            try await self.assertFits(window, step: "\(provider.rawValue) on")
            model.setProviderEnabled(provider, false)
            try await self.assertFits(window, step: "\(provider.rawValue) off")
        }
        try await self.assertFits(window, step: "all providers off")

        model.openAIAccounts = [.defaultAccount(), OpenAIAccountProfile(
            id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", name: "Work", isEnabled: true, storage: .managed
        )]
        try await self.assertFits(window, step: "two OpenAI accounts")
        for account in model.openAIAccounts {
            model.setOpenAIAccountEnabled(id: account.id, enabled: false)
            try await self.assertFits(window, step: "\(account.name) off")
            model.setOpenAIAccountEnabled(id: account.id, enabled: true)
            try await self.assertFits(window, step: "\(account.name) on")
        }
        guard model.openAIAccountError == nil else {
            throw SmokeFailure(message: "Account toggle failed")
        }

        // Verify lifecycle resilience if a host reapplies stale geometry.
        var stale = window.frame
        stale.size.height += 80
        stale.origin.y -= 80
        window.setFrame(stale, display: true)
        try await self.assertFits(window, step: "restored stale frame")
        button.performClick(nil)
        model.setProviderEnabled(.gemini, true)
        try await Task.sleep(for: .milliseconds(100))
        button.performClick(nil)
        try await self.assertFits(window, step: "hidden toggle on, then reopen")
    }

    private func assertFits(_ window: NSWindow, step: String) async throws {
        try await Task.sleep(for: .milliseconds(200))
        let image = ImageRenderer(content: MenuBarRootView(model: Self.model, onOpenSettings: {})).nsImage
        guard let size = image?.size else { throw SmokeFailure(message: "No ideal menu measurement") }
        let actual = window.contentRect(forFrameRect: window.frame).size
        guard window.isVisible, abs(actual.width - size.width) <= 1, abs(actual.height - size.height) <= 1 else {
            throw SmokeFailure(message: "\(step): window \(actual), content \(size), visible \(window.isVisible)")
        }
        print("\(step): window \(actual), content \(size)")
    }

    private func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap { self.statusButton(in: $0) }.first
    }

    private func containsSizingBridge(_ view: NSView?) -> Bool {
        guard let view else { return false }
        return view is MenuWindowSizingView || view.subviews.contains { self.containsSizingBridge($0) }
    }
}

private struct SmokeFailure: Error { let message: String }

@MainActor
@main
struct MenuWindowSizingSmoke: App {
    @NSApplicationDelegateAdaptor(MenuSizingSmokeDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("Sizing Test", systemImage: "ruler") {
            MenuBarRootView(
                model: MenuSizingSmokeDelegate.model,
                onOpenSettings: { MenuSizingSmokeDelegate.settings.showSettings() }
            )
        }
        .menuBarExtraStyle(.window)
    }
}
