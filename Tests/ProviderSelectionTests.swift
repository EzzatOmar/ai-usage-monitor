import XCTest
@testable import AIUsageMonitor

final class ProviderSelectionTests: XCTestCase {
    func test_activeProvidersPreserveDisplayOrderAndDefaultMissingValuesToEnabled() {
        let providerEnabled: [ProviderID: Bool] = [
            .claude: false,
            .gemini: false,
            .cerebras: false,
            .minimax: false,
            .qwenCloud: false,
            .cursor: false,
        ]

        XCTAssertEqual(
            ProviderSelection.activeProviders(providerEnabled: providerEnabled),
            [.codex, .zai, .kimi]
        )
    }

    func test_minimumRemainingPercentIgnoresDisabledProviderResults() {
        let now = Date()
        let results = [
            ProviderUsageResult(
                provider: .claude,
                primaryWindow: UsageWindow(usedPercent: 95, resetAt: nil, windowSeconds: nil),
                lastUpdated: now
            ),
            ProviderUsageResult(
                provider: .codex,
                primaryWindow: UsageWindow(usedPercent: 30, resetAt: nil, windowSeconds: nil),
                lastUpdated: now
            ),
        ]

        XCTAssertEqual(
            ProviderSelection.minimumRemainingPercent(
                results: results,
                providerEnabled: [.claude: false, .codex: true]
            ),
            70
        )
    }

    func test_minimumRemainingPercentUsesEnabledOpenAIAccountIdentity() {
        let now = Date()
        let results = [
            ProviderUsageResult(
                provider: .codex,
                accountID: "personal",
                primaryWindow: UsageWindow(usedPercent: 90, resetAt: nil, windowSeconds: nil),
                lastUpdated: now
            ),
            ProviderUsageResult(
                provider: .codex,
                accountID: "work",
                primaryWindow: UsageWindow(usedPercent: 25, resetAt: nil, windowSeconds: nil),
                lastUpdated: now
            ),
        ]

        XCTAssertEqual(
            ProviderSelection.minimumRemainingPercent(
                results: results,
                activeClientIDs: [ProviderClientID(provider: .codex, accountID: "work")]
            ),
            75
        )
    }

    func test_minimumRemainingPercentIsNilWhenNoActiveProviderHasQuota() {
        let now = Date()
        let results = [
            ProviderUsageResult(
                provider: .claude,
                primaryWindow: UsageWindow(usedPercent: 20, resetAt: nil, windowSeconds: nil),
                lastUpdated: now
            ),
        ]

        XCTAssertNil(
            ProviderSelection.minimumRemainingPercent(
                results: results,
                providerEnabled: Dictionary(
                    uniqueKeysWithValues: ProviderID.allCases.map { ($0, false) }
                )
            )
        )
    }
}
