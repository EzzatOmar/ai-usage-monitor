import Foundation
import Observation

struct UsageMenuRow: Identifiable {
    let id: ProviderClientID
    let provider: ProviderID
    let title: String
    let result: ProviderUsageResult?
}

enum OpenAIAccountLoginState: Equatable {
    case idle
    case authorizing
    case failed(String)
}

@MainActor
@Observable
final class MenuBarViewModel {
    private let store: UsageStore
    private let openAIAuthenticator: any OpenAIAccountAuthenticating
    private var listenTask: Task<Void, Never>?
    private var updateListenTask: Task<Void, Never>?
    private var openAIAccountLoginTasks: [String: Task<Void, Never>] = [:]

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
    var qwenCloudAPIKeyInput: String = ""
    var qwenCloudAPIKeyError: String?
    var showQwenCloudKeyEditor: Bool = false
    var providerEnabled: [ProviderID: Bool] = [:]
    var openAIAccounts: [OpenAIAccountProfile]
    var openAIAccountNameInputs: [String: String]
    var newOpenAIAccountName: String = ""
    var openAIAccountError: String?
    var openAIAccountLoginStates: [String: OpenAIAccountLoginState] = [:]

    init(
        store: UsageStore,
        openAIAccounts: [OpenAIAccountProfile] = OpenAIAccountStore.loadAccounts(),
        openAIAuthenticator: any OpenAIAccountAuthenticating = OpenAIOAuthLoginService.shared
    ) {
        self.store = store
        self.openAIAuthenticator = openAIAuthenticator
        self.openAIAccounts = openAIAccounts
        self.openAIAccountNameInputs = Dictionary(
            uniqueKeysWithValues: openAIAccounts.map { ($0.id, $0.name) }
        )
        self.providerEnabled = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, AuthStore.isProviderEnabled($0)) })
        if let defaultAccount = openAIAccounts.first(where: \.isDefault) {
            self.providerEnabled[.codex] = defaultAccount.isEnabled
        }
        self.start()
    }

    var activeProviders: [ProviderID] {
        ProviderSelection.activeProviders(providerEnabled: self.providerEnabled)
    }

    var activeUsageRows: [UsageMenuRow] {
        ProviderID.allCases.flatMap { provider -> [UsageMenuRow] in
            if provider == .codex {
                return self.openAIAccounts.filter(\.isEnabled).map { account in
                    let id = ProviderClientID(provider: .codex, accountID: account.id)
                    return UsageMenuRow(
                        id: id,
                        provider: .codex,
                        title: account.name,
                        result: self.snapshot.results.first(where: { $0.id == id })
                    )
                }
            }
            guard self.isProviderEnabled(provider) else { return [] }
            let id = ProviderClientID(provider: provider)
            return [UsageMenuRow(
                id: id,
                provider: provider,
                title: provider.rawValue,
                result: self.snapshot.results.first(where: { $0.id == id })
            )]
        }
    }

    var menuBarTitle: String {
        if let minRemaining = ProviderSelection.minimumRemainingPercent(
            results: self.snapshot.results,
            activeClientIDs: Set(self.activeUsageRows.map(\.id))
        ) {
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

    func openAIAccountResult(for accountID: String) -> ProviderUsageResult? {
        self.snapshot.results.first {
            $0.id == ProviderClientID(provider: .codex, accountID: accountID)
        }
    }

    func isOpenAIAccountAuthenticated(_ account: OpenAIAccountProfile) -> Bool {
        OpenAIAuthFileStore.hasCredential(at: account.authURL())
    }

    func addOpenAIAccount() {
        do {
            let updated = try OpenAIAccountStore.addingAccount(
                named: self.newOpenAIAccountName,
                to: self.openAIAccounts
            )
            try OpenAIAccountStore.saveAccounts(updated)
            self.openAIAccounts = updated
            if let added = updated.last {
                self.openAIAccountNameInputs[added.id] = added.name
            }
            self.newOpenAIAccountName = ""
            self.openAIAccountError = nil
            self.refreshNow()
        } catch {
            self.openAIAccountError = error.localizedDescription
        }
    }

    func saveOpenAIAccountName(id: String) {
        do {
            let updated = try OpenAIAccountStore.renamingAccount(
                id: id,
                to: self.openAIAccountNameInputs[id] ?? "",
                in: self.openAIAccounts
            )
            try OpenAIAccountStore.saveAccounts(updated)
            self.openAIAccounts = updated
            self.openAIAccountNameInputs[id] = updated.first(where: { $0.id == id })?.name
            self.openAIAccountError = nil
        } catch {
            self.openAIAccountError = error.localizedDescription
        }
    }

    func setOpenAIAccountEnabled(id: String, enabled: Bool) {
        do {
            let updated = try OpenAIAccountStore.settingAccountEnabled(
                id: id,
                enabled: enabled,
                in: self.openAIAccounts
            )
            try OpenAIAccountStore.saveAccounts(updated)
            self.openAIAccounts = updated
            if id == OpenAIAccountProfile.defaultID {
                self.providerEnabled[.codex] = enabled
                AuthStore.setProviderEnabled(.codex, enabled)
            }
            self.openAIAccountError = nil
            self.refreshNow()
        } catch {
            self.openAIAccountError = error.localizedDescription
        }
    }

    func loginOpenAIAccount(id: String) {
        guard let account = self.openAIAccounts.first(where: { $0.id == id }) else { return }
        self.openAIAccountLoginTasks[id]?.cancel()
        self.openAIAccountLoginStates[id] = .authorizing
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.openAIAuthenticator.login(account: account)
                guard !Task.isCancelled,
                      self.openAIAccounts.contains(where: { $0.id == id })
                else {
                    return
                }
                self.openAIAccountLoginStates[id] = .idle
                self.openAIAccountError = nil
                self.refreshNow()
            } catch is CancellationError {
                if self.openAIAccounts.contains(where: { $0.id == id }) {
                    self.openAIAccountLoginStates[id] = .idle
                }
            } catch let error as OpenAIOAuthLoginError where error == .cancelled {
                if self.openAIAccounts.contains(where: { $0.id == id }) {
                    self.openAIAccountLoginStates[id] = .idle
                }
            } catch {
                if self.openAIAccounts.contains(where: { $0.id == id }) {
                    self.openAIAccountLoginStates[id] = .failed(error.localizedDescription)
                }
            }
            self.openAIAccountLoginTasks.removeValue(forKey: id)
        }
        self.openAIAccountLoginTasks[id] = task
    }

    func cancelOpenAIAccountLogin(id: String) {
        self.openAIAccountLoginTasks[id]?.cancel()
        self.openAIAccountLoginTasks.removeValue(forKey: id)
        self.openAIAccountLoginStates[id] = .idle
        Task {
            await self.openAIAuthenticator.cancel(accountID: id)
        }
    }

    func removeOpenAIAccount(id: String) {
        guard let account = self.openAIAccounts.first(where: { $0.id == id }), !account.isDefault else {
            self.openAIAccountError = OpenAIAccountStoreError.cannotRemoveDefault.localizedDescription
            return
        }
        self.cancelOpenAIAccountLogin(id: id)
        do {
            try OpenAIAccountStore.deleteManagedAuth(for: account)
            let updated = try OpenAIAccountStore.removingAccount(id: id, from: self.openAIAccounts)
            try OpenAIAccountStore.saveAccounts(updated)
            self.openAIAccounts = updated
            self.openAIAccountNameInputs.removeValue(forKey: id)
            self.openAIAccountLoginStates.removeValue(forKey: id)
            self.openAIAccountError = nil
            self.refreshNow()
        } catch {
            self.openAIAccountError = error.localizedDescription
        }
    }

    func enableClaudeKeychainAccess() {
        AuthStore.setClaudeKeychainEnabled(true)
        self.claudeKeychainEnabled = true
        Task {
            await self.store.authorizeCredentials(for: .claude)
        }
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

    func openQwenCloudKeyEditor() {
        self.qwenCloudAPIKeyInput = AuthStore.loadQwenCloudAPIKey() ?? ""
        self.qwenCloudAPIKeyError = nil
        self.showQwenCloudKeyEditor = true
    }

    func saveQwenCloudKey() {
        let trimmed = self.qwenCloudAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            AuthStore.clearQwenCloudAPIKey()
        } else if !AuthStore.saveQwenCloudAPIKey(trimmed) {
            self.qwenCloudAPIKeyError = "Use the Token Plan Individual key beginning with sk-sp-."
            return
        }
        self.qwenCloudAPIKeyError = nil
        self.showQwenCloudKeyEditor = false
        self.refreshNow()
    }

    func cancelQwenCloudKeyEditor() {
        self.qwenCloudAPIKeyError = nil
        self.showQwenCloudKeyEditor = false
    }

    func clearAuth(for provider: ProviderID) {
        switch provider {
        case .claude:
            AuthStore.clearClaudeAuth()
            self.claudeKeychainEnabled = AuthStore.isClaudeKeychainEnabled()
        case .codex:
            AuthStore.clearCodexAuth()
        case .gemini:
            AuthStore.clearGeminiAuth()
        case .zai:
            AuthStore.clearZAIAPIKey()
        case .cerebras:
            AuthStore.clearCerebrasAPIKey()
        case .kimi:
            AuthStore.clearKimiAPIKey()
        case .minimax:
            AuthStore.clearMinimaxAPIKey()
        case .qwenCloud:
            AuthStore.clearQwenCloudAPIKey()
            QwenCloudAPIKeyTransport.shared.clearCachedValidation()
        case .cursor:
            break
        }
        self.refreshNow()
    }

    func isProviderEnabled(_ provider: ProviderID) -> Bool {
        self.providerEnabled[provider] ?? true
    }

    func setProviderEnabled(_ provider: ProviderID, _ enabled: Bool) {
        self.providerEnabled[provider] = enabled
        AuthStore.setProviderEnabled(provider, enabled)
        if enabled {
            self.refreshNow()
        }
    }

    var updateAvailableVersion: String? {
        if case .available(let version, _) = self.updateStatus {
            return version
        }
        return nil
    }

    var showsManualUpdateCheck: Bool {
        self.updateStatus.showsManualUpdateCheck
    }

    func checkForUpdates() {
        Task {
            await UpdateChecker.shared.checkForUpdate()
        }
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
