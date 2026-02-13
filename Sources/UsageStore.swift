import Foundation

protocol ProviderClient: Sendable {
    var providerID: ProviderID { get }
    func fetchUsage(now: Date) async -> ProviderUsageResult
}

actor UsageStore {
    private let clients: [any ProviderClient]
    private let pollIntervalSeconds: UInt64
    private var pollTask: Task<Void, Never>?
    private var snapshot: UsageSnapshot = .empty
    private var continuations: [UUID: AsyncStream<UsageSnapshot>.Continuation] = [:]
    private var lastGood: [ProviderID: ProviderUsageResult] = [:]

    init(clients: [any ProviderClient], pollIntervalSeconds: UInt64 = 60) {
        self.clients = clients
        self.pollIntervalSeconds = pollIntervalSeconds
    }

    deinit {
        self.pollTask?.cancel()
    }

    func updates() -> AsyncStream<UsageSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            self.continuations[id] = continuation
            continuation.yield(self.snapshot)
            continuation.onTermination = { [weak self] _ in
                let actor = self
                Task { await actor?.removeContinuation(id: id) }
            }
        }
    }

    func start() {
        guard self.pollTask == nil else { return }
        self.pollTask = Task {
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.pollIntervalSeconds * 1_000_000_000)
                await self.refresh()
            }
        }
    }

    func stop() {
        self.pollTask?.cancel()
        self.pollTask = nil
    }

    func refreshNow() async {
        await self.refresh()
    }

    private func removeContinuation(id: UUID) {
        self.continuations.removeValue(forKey: id)
    }

    private func refresh() async {
        self.snapshot.isRefreshing = true
        self.publish()

        let now = Date()
        // Start with existing results to preserve order/stale data while refreshing
        var currentResults = self.snapshot.results

        await withTaskGroup(of: ProviderUsageResult.self) { group in
            for client in self.clients {
                group.addTask {
                    await client.fetchUsage(now: now)
                }
            }
            
            for await result in group {
                // Determine the final result for this provider (fresh or stale fallback)
                let finalResult: ProviderUsageResult
                
                if result.errorState == nil {
                    self.lastGood[result.provider] = result
                    finalResult = result
                } else if let cached = self.lastGood[result.provider] {
                    finalResult = ProviderUsageResult(
                        provider: cached.provider,
                        primaryWindow: cached.primaryWindow,
                        secondaryWindow: cached.secondaryWindow,
                        modelWindows: cached.modelWindows,
                        accountLabel: cached.accountLabel,
                        lastUpdated: cached.lastUpdated,
                        errorState: result.errorState,
                        isStale: true
                    )
                } else {
                    finalResult = result
                }
                
                // Update the local results list
                if let index = currentResults.firstIndex(where: { $0.provider == finalResult.provider }) {
                    currentResults[index] = finalResult
                } else {
                    currentResults.append(finalResult)
                }
                
                // Publish intermediate state
                self.snapshot = UsageSnapshot(results: currentResults, lastUpdated: now, isRefreshing: true)
                self.publish()
            }
        }

        self.snapshot = UsageSnapshot(results: currentResults, lastUpdated: now, isRefreshing: false)
        self.publish()
    }

    private func publish() {
        for continuation in self.continuations.values {
            continuation.yield(self.snapshot)
        }
    }
}
