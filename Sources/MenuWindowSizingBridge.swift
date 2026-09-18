import AppKit
import SwiftUI

/// Applies the menu's measured ideal size to its own native window. SwiftUI's
/// fixedSize controls content layout, but does not invalidate a cached window frame.
struct MenuWindowSizingBridge: NSViewRepresentable {
    let contentSize: CGSize

    func makeNSView(context: Context) -> MenuWindowSizingView {
        MenuWindowSizingView()
    }

    func updateNSView(_ view: MenuWindowSizingView, context: Context) {
        view.contentSize = self.contentSize
        view.scheduleResize()
    }
}

@MainActor
final class MenuWindowSizingView: NSView {
    var contentSize: CGSize = .zero
    private var resizeScheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window = self.window {
            // Reapply on reopening and if the host restores an obsolete frame.
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResizeNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(self.windowGeometryChanged), name: name, object: window
                )
            }
        }
        self.scheduleResize()
    }

    @objc private func windowGeometryChanged(_ notification: Notification) {
        self.scheduleResize()
    }

    func scheduleResize() {
        guard !self.resizeScheduled else { return }
        self.resizeScheduled = true
        // Let SwiftUI finish its layout transaction before changing AppKit geometry.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizeScheduled = false
            self.resizeWindowToContent()
        }
    }

    private func resizeWindowToContent() {
        guard let window = self.window,
              self.contentSize.width.isFinite, self.contentSize.height.isFinite,
              self.contentSize.width > 0, self.contentSize.height > 0
        else { return }

        let desiredContent = NSRect(origin: .zero, size: CGSize(
            width: ceil(self.contentSize.width), height: ceil(self.contentSize.height)
        ))
        let desiredSize = window.frameRect(forContentRect: desiredContent).size
        let previous = window.frame
        guard abs(previous.width - desiredSize.width) > 0.5 ||
              abs(previous.height - desiredSize.height) > 0.5
        else { return }

        // Grow down from the status item instead of moving the menu's top edge.
        let frame = NSRect(
            x: previous.minX, y: previous.maxY - desiredSize.height,
            width: desiredSize.width, height: desiredSize.height
        )
        window.setFrame(frame, display: window.isVisible, animate: false)
    }
}
