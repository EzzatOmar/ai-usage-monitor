import AppKit
import SwiftUI
import XCTest
@testable import AIUsageMonitor

final class MenuWindowSizingTests: XCTestCase {
    @MainActor
    func test_nativeWindowTracksRowsWithoutAutomaticHostingSizeConstraints() async throws {
        let model = MenuBarViewModel(
            store: UsageStore(clients: [], pollIntervalSeconds: 3600),
            openAIAccounts: [.defaultAccount(isEnabled: false)]
        )
        let providers: [ProviderID] = [.claude, .gemini, .zai, .kimi, .openCodeGo]
        model.providerEnabled = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map {
            ($0, providers.contains($0))
        })
        let host = NSHostingController(rootView: MenuBarRootView(model: model, onOpenSettings: {}))
        // Simulate MenuBarExtra keeping its old frame: no automatic min/max/intrinsic sizing.
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 340, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentViewController = host
        window.setContentSize(host.sizeThatFits(in: CGSize(width: 340, height: 0)))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        try await self.assertWindowFitsMenu(window, model: model)
        let fiveRows = window.frame
        model.providerEnabled[.kimi] = false
        try await self.assertWindowFitsMenu(window, model: model)
        let fourRows = window.frame
        XCTAssertLessThan(fourRows.height, fiveRows.height)
        XCTAssertEqual(fourRows.maxY, fiveRows.maxY, accuracy: 1)
        XCTAssertEqual(fourRows.minX, fiveRows.minX, accuracy: 1)

        // Hidden updates must not require recreating the scene or restarting the app.
        window.orderOut(nil)
        model.providerEnabled[.zai] = false
        try await Task.sleep(for: .milliseconds(50))
        window.orderFrontRegardless()
        try await self.assertWindowFitsMenu(window, model: model)
        XCTAssertLessThan(window.frame.height, fourRows.height)

        // A host restoring cached geometry on reopen must be corrected even if the
        // SwiftUI content size hasn't changed since its last measurement.
        window.setFrame(fiveRows, display: true)
        try await self.assertWindowFitsMenu(window, model: model)
        XCTAssertLessThan(window.frame.height, fourRows.height)

        for _ in 0..<3 {
            model.providerEnabled = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, false) })
            try await self.assertWindowFitsMenu(window, model: model)
            let emptyHeight = window.frame.height
            model.providerEnabled = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map {
                ($0, providers.contains($0))
            })
            try await self.assertWindowFitsMenu(window, model: model)
            XCTAssertGreaterThan(window.frame.height, emptyHeight)
            XCTAssertEqual(window.frame.height, fiveRows.height, accuracy: 1)
        }

        model.openAIAccounts = [.defaultAccount(), OpenAIAccountProfile(
            id: "work", name: "Work", isEnabled: true, storage: .managed
        )]
        try await self.assertWindowFitsMenu(window, model: model)
        let twoAccountsHeight = window.frame.height
        model.openAIAccounts[1].isEnabled = false
        try await self.assertWindowFitsMenu(window, model: model)
        XCTAssertLessThan(window.frame.height, twoAccountsHeight)

        let pendingHeight = window.frame.height
        model.snapshot = UsageSnapshot(results: [ProviderUsageResult(
            provider: .claude,
            primaryWindow: UsageWindow(usedPercent: 20, resetAt: nil, windowSeconds: nil),
            secondaryWindow: UsageWindow(usedPercent: 30, resetAt: nil, windowSeconds: nil),
            accountLabel: "person@example.com", lastUpdated: Date(),
            errorState: .networkError("Unable to refresh usage. Please check your connection."),
            isStale: true
        )], lastUpdated: Date(), isRefreshing: false)
        try await self.assertWindowFitsMenu(window, model: model)
        XCTAssertGreaterThan(window.frame.height, pendingHeight)
        model.snapshot = .empty
        try await self.assertWindowFitsMenu(window, model: model)
        XCTAssertEqual(window.frame.height, pendingHeight, accuracy: 1)
    }

    @MainActor
    func test_sizingBridgeOnlyResizesItsAttachedWindowAndIgnoresInvalidMeasurements() async throws {
        let first = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 340, height: 500),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        let second = NSWindow(contentRect: NSRect(x: 500, y: 100, width: 340, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let bridge = MenuWindowSizingView()
        bridge.contentSize = CGSize(width: 340, height: 200)
        first.contentView?.addSubview(bridge)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(first.frame.height, 200)
        XCTAssertEqual(second.frame.height, 500)

        bridge.removeFromSuperview()
        first.setContentSize(CGSize(width: 340, height: 450))
        second.contentView?.addSubview(bridge)
        bridge.contentSize = CGSize(width: 340, height: 250)
        bridge.scheduleResize()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(first.frame.height, 450)
        XCTAssertEqual(second.frame.height, 250)

        for size in [CGSize.zero, CGSize(width: 340, height: CGFloat.nan)] {
            bridge.contentSize = size
            bridge.scheduleResize()
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(second.frame.height, 250)
        }
        bridge.removeFromSuperview()
    }

    @MainActor
    private func assertWindowFitsMenu(
        _ window: NSWindow, model: MenuBarViewModel,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        // Allow observation, SwiftUI layout, and the deferred AppKit resize to settle.
        try await Task.sleep(for: .milliseconds(100))
        let renderer = ImageRenderer(content: MenuBarRootView(model: model, onOpenSettings: {}))
        let expected = try XCTUnwrap(renderer.nsImage, file: file, line: line).size
        let actual = window.contentRect(forFrameRect: window.frame).size
        XCTAssertEqual(actual.width, expected.width, accuracy: 1, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 1, file: file, line: line)
    }
}
