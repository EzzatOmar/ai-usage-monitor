import AppKit
import SwiftUI

/// AppKit shell that reliably presents SwiftUI settings from an accessory menu bar app.
@MainActor
final class SettingsWindowPresenter {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("AIUsageMonitor.Settings")

    private let model: MenuBarViewModel
    private var windowController: NSWindowController?

    init(model: MenuBarViewModel) {
        self.model = model
    }

    var settingsWindow: NSWindow? {
        self.windowController?.window
    }

    func showSettings() {
        let window = self.windowController?.window ?? self.makeSettingsWindow()

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    func closeSettings() {
        self.windowController?.close()
    }

    private func makeSettingsWindow() -> NSWindow {
        let contentSize = NSSize(width: 480, height: 620)
        let hostingController = NSHostingController(
            rootView: SettingsRootView(model: self.model)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = Self.windowIdentifier
        window.title = "AI Usage Monitor Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.tabbingMode = .disallowed
        window.center()

        let controller = NSWindowController(window: window)
        self.windowController = controller
        return window
    }
}
