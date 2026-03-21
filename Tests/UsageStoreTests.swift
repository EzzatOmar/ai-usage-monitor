import XCTest
@testable import AIUsageMonitor

private struct StubClient: ProviderClient {
    let providerID: ProviderID
    let responses: [ProviderUsageResult]
    let onFetch: (@Sendable () -> Void)?

    init(providerID: ProviderID, responses: [ProviderUsageResult], onFetch: (@Sendable () -> Void)? = nil) {
        self.providerID = providerID
        self.responses = responses
        self.onFetch = onFetch
    }

    func fetchUsage(now: Date, mode _: UsageRefreshMode) async -> ProviderUsageResult {
        self.onFetch?()
        if self.responses.count <= 1 {
            return self.responses.first ?? ProviderUsageResult(provider: self.providerID, lastUpdated: now)
        }

        let index = min(FetchCounter.nextIndex(for: self.providerID), self.responses.count - 1)
        return self.responses[index]
    }
}

private enum FetchCounter {
    static let lock = NSLock()
    static var values: [ProviderID: Int] = [:]

    static func nextIndex(for providerID: ProviderID) -> Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        let current = self.values[providerID, default: 0]
        self.values[providerID] = current + 1
        return current
    }

    static func reset() {
        self.lock.lock()
        self.values = [:]
        self.lock.unlock()
    }
}

final class UsageStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        FetchCounter.reset()
    }

    func test_storePublishesResultsForAllProviders() async {
        let now = Date()
        let store = UsageStore(clients: [
            StubClient(providerID: .claude, responses: [ProviderUsageResult(provider: .claude, primaryWindow: UsageWindow(usedPercent: 10, resetAt: now, windowSeconds: 18000), secondaryWindow: nil, accountLabel: nil, lastUpdated: now, errorState: nil, isStale: false)]),
            StubClient(providerID: .codex, responses: [ProviderUsageResult(provider: .codex, primaryWindow: UsageWindow(usedPercent: 20, resetAt: now, windowSeconds: 18000), secondaryWindow: nil, accountLabel: nil, lastUpdated: now, errorState: nil, isStale: false)]),
            StubClient(providerID: .gemini, responses: [ProviderUsageResult(provider: .gemini, primaryWindow: UsageWindow(usedPercent: 30, resetAt: now, windowSeconds: 86400), secondaryWindow: nil, accountLabel: nil, lastUpdated: now, errorState: nil, isStale: false)]),
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

    func test_storeRetriesScheduledRefreshOnRateLimit() async {
        let now = Date()
        let fetches = LockedInt()
        let sleeps = LockedInt()
        let store = UsageStore(
            clients: [
                StubClient(providerID: .codex, responses: [
                    ProviderUsageResult(provider: .codex, lastUpdated: now, errorState: .rateLimited("HTTP 429", retryAfter: 1), isStale: false),
                    ProviderUsageResult(provider: .codex, primaryWindow: UsageWindow(usedPercent: 25, resetAt: now, windowSeconds: 18000), lastUpdated: now, errorState: nil, isStale: false),
                ], onFetch: { fetches.increment() }),
            ],
            pollIntervalSeconds: 3600,
            retrySleep: { _ in sleeps.increment() }
        )

        await store.start()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await store.stop()
        let snapshot = await firstSnapshot(from: store)

        XCTAssertEqual(fetches.value, 2)
        XCTAssertEqual(sleeps.value, 1)
        XCTAssertNil(snapshot.results.first?.errorState)
    }

    func test_manualRefreshDoesNotRetryOnRateLimit() async {
        let now = Date()
        let fetches = LockedInt()
        let sleeps = LockedInt()
        let store = UsageStore(
            clients: [
                StubClient(providerID: .codex, responses: [
                    ProviderUsageResult(provider: .codex, lastUpdated: now, errorState: .rateLimited("HTTP 429", retryAfter: 1), isStale: false),
                    ProviderUsageResult(provider: .codex, primaryWindow: UsageWindow(usedPercent: 25, resetAt: now, windowSeconds: 18000), lastUpdated: now, errorState: nil, isStale: false),
                ], onFetch: { fetches.increment() }),
            ],
            pollIntervalSeconds: 3600,
            retrySleep: { _ in sleeps.increment() }
        )

        await store.refreshNow()
        let snapshot = await firstSnapshot(from: store)

        XCTAssertEqual(fetches.value, 1)
        XCTAssertEqual(sleeps.value, 0)
        XCTAssertTrue(snapshot.results.first?.errorState?.isRateLimited == true)
    }

    private func firstSnapshot(from store: UsageStore) async -> UsageSnapshot {
        let stream = await store.updates()
        for await value in stream {
            if !value.isRefreshing {
                return value
            }
        }
        return .empty
    }
}

private final class LockedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.storage
    }

    func increment() {
        self.lock.lock()
        self.storage += 1
        self.lock.unlock()
    }
}
