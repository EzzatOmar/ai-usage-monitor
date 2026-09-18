import SwiftUI
import XCTest
@testable import AIUsageMonitor

final class UIRenderingTests: XCTestCase {
    @MainActor
    func test_settingsRootViewRendersWithEveryProviderConfigurationRow() {
        let model = self.makeModel()
        let managed = OpenAIAccountProfile(
            id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            name: "Work",
            isEnabled: true,
            storage: .managed
        )
        model.openAIAccounts.append(managed)
        model.openAIAccountNameInputs[managed.id] = managed.name
        let renderer = ImageRenderer(content: SettingsRootView(model: model))
        renderer.proposedSize = ProposedViewSize(width: 480, height: 620)

        XCTAssertNotNil(renderer.nsImage)
        XCTAssertEqual(ProviderID.allCases.count, 10)
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
                    accountID: OpenAIAccountProfile.defaultID,
                    primaryWindow: UsageWindow(usedPercent: 25, resetAt: nil, windowSeconds: nil),
                    lastUpdated: Date()
                ),
            ],
            lastUpdated: Date(),
            isRefreshing: false
        )
        let renderer = ImageRenderer(
            content: MenuBarRootView(model: model, onOpenSettings: {})
        )
        renderer.proposedSize = ProposedViewSize(width: 340, height: nil)

        XCTAssertEqual(model.activeProviders, [.codex])
        XCTAssertEqual(model.menuBarTitle, "AI 75%")
        XCTAssertNotNil(renderer.nsImage)
    }

    @MainActor
    func test_menuBarRootViewRendersNamedOpenAIAccountsAsIndependentRows() {
        let model = self.makeModel()
        let work = OpenAIAccountProfile(
            id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            name: "Work",
            isEnabled: true,
            storage: .managed
        )
        model.providerEnabled = Dictionary(
            uniqueKeysWithValues: ProviderID.allCases.map { ($0, false) }
        )
        model.openAIAccounts = [
            .defaultAccount(name: "Personal"),
            work,
        ]
        model.snapshot = UsageSnapshot(
            results: [
                ProviderUsageResult(
                    provider: .codex,
                    accountID: OpenAIAccountProfile.defaultID,
                    primaryWindow: UsageWindow(usedPercent: 30, resetAt: nil, windowSeconds: nil),
                    lastUpdated: Date()
                ),
                ProviderUsageResult(
                    provider: .codex,
                    accountID: work.id,
                    primaryWindow: UsageWindow(usedPercent: 60, resetAt: nil, windowSeconds: nil),
                    lastUpdated: Date()
                ),
            ],
            lastUpdated: Date(),
            isRefreshing: false
        )
        let renderer = ImageRenderer(
            content: MenuBarRootView(model: model, onOpenSettings: {})
        )
        renderer.proposedSize = ProposedViewSize(width: 340, height: nil)

        XCTAssertEqual(model.activeUsageRows.map(\.title), ["Personal", "Work"])
        XCTAssertEqual(model.menuBarTitle, "AI 40%")
        XCTAssertNotNil(renderer.nsImage)
    }

    @MainActor
    func test_openCodeGoRendersThreeWindowsAndKeyEditor() {
        let model = self.makeModel()
        model.providerEnabled = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, $0 == .openCodeGo) })
        model.openAIAccounts = [.defaultAccount(isEnabled: false)]
        model.snapshot = UsageSnapshot(results: [ProviderUsageResult(
            provider: .openCodeGo,
            primaryWindow: UsageWindow(usedPercent: 10, resetAt: nil, windowSeconds: 18_000),
            secondaryWindow: UsageWindow(usedPercent: 20, resetAt: nil, windowSeconds: 604_800),
            tertiaryWindow: UsageWindow(usedPercent: 90, resetAt: nil, windowSeconds: nil),
            lastUpdated: Date()
        )], lastUpdated: Date(), isRefreshing: false)
        let menu = ImageRenderer(content: MenuBarRootView(model: model, onOpenSettings: {}))
        XCTAssertNotNil(menu.nsImage)
        XCTAssertEqual(model.activeUsageRows.map(\.provider), [.openCodeGo])
        XCTAssertEqual(model.menuBarTitle, "AI 10%")
        model.showOpenCodeGoKeyEditor = true
        let settings = ImageRenderer(content: SettingsRootView(model: model))
        XCTAssertNotNil(settings.nsImage)
        model.openCodeGoAPIKeyInput = "test-secret"
        model.cancelOpenCodeGoKeyEditor()
        XCTAssertFalse(model.showOpenCodeGoKeyEditor)
        XCTAssertEqual(model.openCodeGoAPIKeyInput, "")
    }

    @MainActor
    func test_menuBarRootViewRendersWhenEveryProviderIsDisabled() {
        let model = self.makeModel()
        model.providerEnabled = Dictionary(
            uniqueKeysWithValues: ProviderID.allCases.map { ($0, false) }
        )
        model.openAIAccounts = [.defaultAccount(isEnabled: false)]
        let renderer = ImageRenderer(
            content: MenuBarRootView(model: model, onOpenSettings: {})
        )
        renderer.proposedSize = ProposedViewSize(width: 340, height: nil)

        XCTAssertTrue(model.activeProviders.isEmpty)
        XCTAssertEqual(model.menuBarTitle, "AI --")
        XCTAssertNotNil(renderer.nsImage)
    }

    @MainActor
    func test_hostedMenuWindowShrinksAfterDisablingProvider() async throws {
        let model = self.makeModel()
        let providers: [ProviderID] = [.claude, .gemini, .zai, .kimi, .openCodeGo]
        model.providerEnabled = Dictionary(
            uniqueKeysWithValues: ProviderID.allCases.map { ($0, providers.contains($0)) }
        )
        model.openAIAccounts = [.defaultAccount(isEnabled: false)]
        model.snapshot = UsageSnapshot(results: providers.map { provider in
            ProviderUsageResult(
                provider: provider,
                primaryWindow: UsageWindow(usedPercent: 20, resetAt: nil, windowSeconds: nil),
                secondaryWindow: UsageWindow(usedPercent: 30, resetAt: nil, windowSeconds: nil),
                accountLabel: "person@example.com",
                lastUpdated: Date(),
                errorState: .networkError("The request could not be completed. Check your network connection and try again."),
                isStale: true
            )
        }, lastUpdated: Date(), isRefreshing: true)
        let host = NSHostingController(rootView: MenuBarRootView(model: model, onOpenSettings: {}))
        host.sizingOptions = [.minSize, .maxSize]
        let window = NSWindow(contentViewController: host)
        defer { window.orderOut(nil) }
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(100))
        window.contentView?.layoutSubtreeIfNeeded()
        let originalHeight = try XCTUnwrap(window.contentView).frame.height

        model.providerEnabled[.kimi] = false
        try await Task.sleep(for: .milliseconds(100))
        window.contentView?.layoutSubtreeIfNeeded()
        let smallerHeight = try XCTUnwrap(window.contentView).frame.height
        XCTAssertLessThan(smallerHeight, originalHeight)
        XCTAssertEqual(smallerHeight, host.sizeThatFits(in: CGSize(width: 340, height: 0)).height, accuracy: 1)

        window.orderOut(nil)
        model.providerEnabled[.zai] = false
        try await Task.sleep(for: .milliseconds(100))
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(100))
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertLessThan(try XCTUnwrap(window.contentView).frame.height, smallerHeight)
    }

    @MainActor
    func test_menuHeightTracksProviderChangesDespitePreviousHostHeight() throws {
        let model = self.makeModel()
        let providers: [ProviderID] = [.claude, .gemini, .zai, .kimi, .openCodeGo]
        model.providerEnabled = Dictionary(
            uniqueKeysWithValues: ProviderID.allCases.map { ($0, providers.contains($0)) }
        )
        model.openAIAccounts = [.defaultAccount(isEnabled: false)]
        let renderer = ImageRenderer(content: MenuBarRootView(model: model, onOpenSettings: {}))

        func renderedSize(proposedHeight: CGFloat?) throws -> CGSize {
            renderer.proposedSize = ProposedViewSize(width: 340, height: proposedHeight)
            return try XCTUnwrap(renderer.nsImage).size
        }

        let fiveProviders = try renderedSize(proposedHeight: nil)
        model.providerEnabled[.kimi] = false
        let fourProviders = try renderedSize(proposedHeight: fiveProviders.height)
        XCTAssertLessThan(fourProviders.height, fiveProviders.height)
        XCTAssertEqual(fourProviders.height, try renderedSize(proposedHeight: nil).height)
        XCTAssertEqual(fourProviders.width, 340)

        model.providerEnabled = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, false) })
        let empty = try renderedSize(proposedHeight: fourProviders.height)
        XCTAssertLessThan(empty.height, fourProviders.height)
        XCTAssertEqual(empty.height, try renderedSize(proposedHeight: nil).height)

        model.providerEnabled = Dictionary(
            uniqueKeysWithValues: ProviderID.allCases.map { ($0, providers.contains($0)) }
        )
        XCTAssertEqual(try renderedSize(proposedHeight: empty.height), fiveProviders)
    }

    @MainActor
    func test_menuHeightTracksNamedAccountAndQuotaDetailChanges() throws {
        let model = self.makeModel()
        model.providerEnabled = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, false) })
        model.openAIAccounts = [
            .defaultAccount(),
            OpenAIAccountProfile(id: "work", name: "Work", isEnabled: true, storage: .managed),
        ]
        let renderer = ImageRenderer(content: MenuBarRootView(model: model, onOpenSettings: {}))
        let twoAccounts = try XCTUnwrap(renderer.nsImage).size

        model.openAIAccounts[1].isEnabled = false
        renderer.proposedSize = ProposedViewSize(width: 340, height: twoAccounts.height)
        let oneAccount = try XCTUnwrap(renderer.nsImage).size
        XCTAssertLessThan(oneAccount.height, twoAccounts.height)

        model.snapshot = UsageSnapshot(results: [ProviderUsageResult(
            provider: .codex,
            accountID: OpenAIAccountProfile.defaultID,
            primaryWindow: UsageWindow(usedPercent: 10, resetAt: nil, windowSeconds: nil),
            secondaryWindow: UsageWindow(usedPercent: 20, resetAt: nil, windowSeconds: nil),
            lastUpdated: Date()
        )], lastUpdated: Date(), isRefreshing: false)
        renderer.proposedSize = ProposedViewSize(width: 340, height: oneAccount.height)
        let expanded = try XCTUnwrap(renderer.nsImage).size
        XCTAssertGreaterThan(expanded.height, oneAccount.height)

        model.snapshot = .empty
        renderer.proposedSize = ProposedViewSize(width: 340, height: expanded.height)
        XCTAssertEqual(try XCTUnwrap(renderer.nsImage).size, oneAccount)
    }

    @MainActor
    func test_settingsWindowPresenterOpensReusesAndReopensOneWindow() {
        let model = self.makeModel()
        let presenter = SettingsWindowPresenter(model: model)
        defer { presenter.closeSettings() }

        XCTAssertNil(presenter.settingsWindow)

        presenter.showSettings()
        let firstWindow = presenter.settingsWindow
        let hostingController = firstWindow?.contentViewController as? NSHostingController<SettingsRootView>

        XCTAssertNotNil(firstWindow)
        XCTAssertTrue(firstWindow?.isVisible == true)
        XCTAssertTrue(firstWindow?.canBecomeKey == true)
        XCTAssertTrue(hostingController?.rootView.model === model)

        presenter.showSettings()
        XCTAssertTrue(firstWindow === presenter.settingsWindow)

        presenter.closeSettings()
        XCTAssertTrue(firstWindow?.isVisible == false)

        presenter.showSettings()
        XCTAssertTrue(firstWindow === presenter.settingsWindow)
        XCTAssertTrue(firstWindow?.isVisible == true)
        XCTAssertTrue(firstWindow?.canBecomeKey == true)
    }

    @MainActor
    private func makeModel() -> MenuBarViewModel {
        MenuBarViewModel(
            store: UsageStore(clients: [], pollIntervalSeconds: 3_600),
            openAIAccounts: [.defaultAccount()]
        )
    }
}
