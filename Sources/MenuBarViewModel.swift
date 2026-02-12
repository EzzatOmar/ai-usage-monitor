import Foundation
import Observation

@MainActor
@Observable
final class MenuBarViewModel {
    private let store: UsageStore
    private var listenTask: Task<Void, Never>?

    var snapshot: UsageSnapshot = .empty

    init(store: UsageStore) {
        self.store = store
        self.start()
    }

    var menuBarTitle: String {
        if let minRemaining = self.snapshot.minimumRemainingPercent {
            return "AI \(Int(minRemaining.rounded()))%"
        }
        return "AI --"
    }

    var menuBarSystemImage: String {
        if self.snapshot.results.contains(where: { $0.errorState != nil }) {
            return "exclamationmark.triangle"
        }
        return "chart.pie"
    }

    func refreshNow() {
        Task {
            await self.store.refreshNow()
        }
    }

    private func start() {
        self.listenTask = Task {
            await self.store.start()
            let stream = await self.store.updates()
            for await update in stream {
                self.snapshot = update
            }
        }
    }
}
