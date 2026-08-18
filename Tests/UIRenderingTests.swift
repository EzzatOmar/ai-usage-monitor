import SwiftUI
import XCTest
@testable import AIUsageMonitor

final class UIRenderingTests: XCTestCase {
    @MainActor
    func test_settingsRootViewRendersWithEveryProviderConfigurationRow() {
        let model = self.makeModel()
        let renderer = ImageRenderer(content: SettingsRootView(model: model))
        renderer.proposedSize = ProposedViewSize(width: 480, height: 620)

        XCTAssertNotNil(renderer.nsImage)
        XCTAssertEqual(ProviderID.allCases.count, 9)
    }

    @MainActor
    func test_menuBarRootViewRendersWithOnlySelectedProviders() {
        let model = self.makeModel()
        model.providerEnabled = Dictionary(
            uniqueKeysWithValues: ProviderID.allCases.map { ($0, $0 == .codex) }
        )
        model.snapshot = UsageSnapshot(
            results: [
                ProviderUsageResult(
                    provider: .claude,
                    primaryWindow: UsageWindow(usedPercent: 95, resetAt: nil, windowSeconds: nil),
                    lastUpdated: Date()
                ),
                ProviderUsageResult(
                    provider: .codex,
                    primaryWindow: UsageWindow(usedPercent: 25, resetAt: nil, windowSeconds: nil),
                    lastUpdated: Date()
                ),
            ],
            lastUpdated: Date(),
            isRefreshing: false
        )
        let renderer = ImageRenderer(content: MenuBarRootView(model: model))
        renderer.proposedSize = ProposedViewSize(width: 340, height: nil)

        XCTAssertEqual(model.activeProviders, [.codex])
        XCTAssertEqual(model.menuBarTitle, "AI 75%")
        XCTAssertNotNil(renderer.nsImage)
    }

    @MainActor
    func test_menuBarRootViewRendersWhenEveryProviderIsDisabled() {
        let model = self.makeModel()
        model.providerEnabled = Dictionary(
            uniqueKeysWithValues: ProviderID.allCases.map { ($0, false) }
        )
        let renderer = ImageRenderer(content: MenuBarRootView(model: model))
        renderer.proposedSize = ProposedViewSize(width: 340, height: nil)

        XCTAssertTrue(model.activeProviders.isEmpty)
        XCTAssertEqual(model.menuBarTitle, "AI --")
        XCTAssertNotNil(renderer.nsImage)
    }

    @MainActor
    private func makeModel() -> MenuBarViewModel {
        MenuBarViewModel(
            store: UsageStore(clients: [], pollIntervalSeconds: 3_600)
        )
    }
}
