import Foundation
import Observation

@MainActor
@Observable
final class MenuBarViewModel {
    private let store: UsageStore
    private var listenTask: Task<Void, Never>?

    var snapshot: UsageSnapshot = .empty
    var claudeKeychainEnabled: Bool = AuthStore.isClaudeKeychainEnabled()
    var claudeSetupTokenInput: String = ""
    var showClaudeTokenEditor: Bool = false
    var zaiAPIKeyInput: String = ""
    var showZAIKeyEditor: Bool = false
    var cerebrasAPIKeyInput: String = ""
    var showCerebrasKeyEditor: Bool = false

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

    func openClaudeTokenEditor() {
        self.claudeSetupTokenInput = AuthStore.loadClaudeSetupToken() ?? ""
        self.showClaudeTokenEditor = true
    }

    func saveClaudeToken() {
        let trimmed = self.claudeSetupTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            AuthStore.clearClaudeSetupToken()
        } else {
            _ = AuthStore.saveClaudeSetupToken(trimmed)
        }
        self.showClaudeTokenEditor = false
        self.refreshNow()
    }

    func enableClaudeKeychainAccess() {
        AuthStore.setClaudeKeychainEnabled(true)
        self.claudeKeychainEnabled = true
        self.refreshNow()
    }

    func cancelClaudeTokenEditor() {
        self.showClaudeTokenEditor = false
    }

    func openZAIKeyEditor() {
        self.zaiAPIKeyInput = AuthStore.loadZAIAPIKey() ?? ""
        self.showZAIKeyEditor = true
    }

    func saveZAIKey() {
        let trimmed = self.zaiAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            AuthStore.clearZAIAPIKey()
        } else {
            _ = AuthStore.saveZAIAPIKey(trimmed)
        }
        self.showZAIKeyEditor = false
        self.refreshNow()
    }

    func cancelZAIKeyEditor() {
        self.showZAIKeyEditor = false
    }

    func openCerebrasKeyEditor() {
        self.cerebrasAPIKeyInput = AuthStore.loadCerebrasAPIKey() ?? ""
        self.showCerebrasKeyEditor = true
    }

    func saveCerebrasKey() {
        let trimmed = self.cerebrasAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            AuthStore.clearCerebrasAPIKey()
        } else {
            _ = AuthStore.saveCerebrasAPIKey(trimmed)
        }
        self.showCerebrasKeyEditor = false
        self.refreshNow()
    }

    func cancelCerebrasKeyEditor() {
        self.showCerebrasKeyEditor = false
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
