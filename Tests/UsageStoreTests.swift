import XCTest
@testable import AIUsageMonitor

private struct StubClient: ProviderClient {
    let providerID: ProviderID
    let response: ProviderUsageResult

    func fetchUsage(now: Date) async -> ProviderUsageResult {
        self.response
    }
}

final class UsageStoreTests: XCTestCase {
    func test_storePublishesResultsForAllProviders() async {
        let now = Date()
        let store = UsageStore(clients: [
            StubClient(providerID: .claude, response: ProviderUsageResult(provider: .claude, primaryWindow: UsageWindow(usedPercent: 10, resetAt: now, windowSeconds: 18000), secondaryWindow: nil, accountLabel: nil, lastUpdated: now, errorState: nil, isStale: false)),
            StubClient(providerID: .codex, response: ProviderUsageResult(provider: .codex, primaryWindow: UsageWindow(usedPercent: 20, resetAt: now, windowSeconds: 18000), secondaryWindow: nil, accountLabel: nil, lastUpdated: now, errorState: nil, isStale: false)),
            StubClient(providerID: .gemini, response: ProviderUsageResult(provider: .gemini, primaryWindow: UsageWindow(usedPercent: 30, resetAt: now, windowSeconds: 86400), secondaryWindow: nil, accountLabel: nil, lastUpdated: now, errorState: nil, isStale: false)),
        ], pollIntervalSeconds: 3600)

        await store.refreshNow()
        let stream = await store.updates()
        var latest: UsageSnapshot?
        for await value in stream {
            latest = value
            break
        }
        XCTAssertEqual(latest?.results.count, 3)
    }
}
