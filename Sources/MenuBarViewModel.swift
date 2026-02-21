import Foundation
import Observation

@MainActor
@Observable
final class MenuBarViewModel {
    private let store: UsageStore
    private var listenTask: Task<Void, Never>?
    private var updateListenTask: Task<Void, Never>?

    var snapshot: UsageSnapshot = .empty
    var updateStatus: UpdateStatus = .unknown
    var claudeKeychainEnabled: Bool = AuthStore.isClaudeKeychainEnabled()
    var zaiAPIKeyInput: String = ""
    var showZAIKeyEditor: Bool = false
    var cerebrasAPIKeyInput: String = ""
    var showCerebrasKeyEditor: Bool = false
    var kimiAPIKeyInput: String = ""
    var showKimiKeyEditor: Bool = false
    var minimaxAPIKeyInput: String = ""
    var showMinimaxKeyEditor: Bool = false

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
        "chart.pie"
    }

    func refreshNow() {
        Task {
            await self.store.refreshNow()
        }
    }

    func enableClaudeKeychainAccess() {
        AuthStore.setClaudeKeychainEnabled(true)
        self.claudeKeychainEnabled = true
        self.refreshNow()
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

    func openKimiKeyEditor() {
        self.kimiAPIKeyInput = AuthStore.loadKimiAPIKey() ?? ""
        self.showKimiKeyEditor = true
    }

    func saveKimiKey() {
        let trimmed = self.kimiAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            AuthStore.clearKimiAPIKey()
        } else {
            _ = AuthStore.saveKimiAPIKey(trimmed)
        }
        self.showKimiKeyEditor = false
        self.refreshNow()
    }

    func cancelKimiKeyEditor() {
        self.showKimiKeyEditor = false
    }

    func openMinimaxKeyEditor() {
        self.minimaxAPIKeyInput = AuthStore.loadMinimaxAPIKey() ?? ""
        self.showMinimaxKeyEditor = true
    }

    func saveMinimaxKey() {
        let trimmed = self.minimaxAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            AuthStore.clearMinimaxAPIKey()
        } else {
            _ = AuthStore.saveMinimaxAPIKey(trimmed)
        }
        self.showMinimaxKeyEditor = false
        self.refreshNow()
    }

    func cancelMinimaxKeyEditor() {
        self.showMinimaxKeyEditor = false
    }

    var updateAvailableVersion: String? {
        if case .available(let version, _) = self.updateStatus {
            return version
        }
        return nil
    }

    func triggerUpdate() {
        Task {
            await UpdateChecker.shared.triggerDownloadAndInstall()
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
        self.updateListenTask = Task {
            await UpdateChecker.shared.start()
            let stream = await UpdateChecker.shared.statusUpdates()
            for await status in stream {
                self.updateStatus = status
            }
        }
    }
}
