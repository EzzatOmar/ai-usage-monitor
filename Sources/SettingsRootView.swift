import SwiftUI

@MainActor
struct SettingsRootView: View {
    @Bindable var model: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Providers")
                    .font(.title2.weight(.semibold))
                Text("Choose which providers appear in the usage menu and configure their credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(ProviderID.allCases, id: \.self) { provider in
                        if provider == .codex {
                            OpenAIAccountsSettingsSection(model: self.model)
                        } else {
                            ProviderSettingsRow(
                                provider: provider,
                                isEnabled: Binding(
                                    get: { self.model.isProviderEnabled(provider) },
                                    set: { self.model.setProviderEnabled(provider, $0) }
                                ),
                                claudeKeychainEnabled: self.model.claudeKeychainEnabled,
                                onClaudeKeychainAccess: { self.model.enableClaudeKeychainAccess() },
                                onSetKey: { self.openKeyEditor(for: provider) },
                                onRemoveKey: { self.model.clearAuth(for: provider) }
                            )

                            self.keyEditor(for: provider)
                        }

                        if provider != ProviderID.allCases.last {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            Divider()

            UpdateSettingsSection(model: self.model)
        }
        .padding(16)
        .frame(width: 480, height: 620)
    }

    private func openKeyEditor(for provider: ProviderID) {
        switch provider {
        case .zai:
            self.model.openZAIKeyEditor()
        case .cerebras:
            self.model.openCerebrasKeyEditor()
        case .kimi:
            self.model.openKimiKeyEditor()
        case .minimax:
            self.model.openMinimaxKeyEditor()
        case .qwenCloud:
            self.model.openQwenCloudKeyEditor()
        case .claude, .codex, .gemini, .cursor:
            break
        }
    }

    @ViewBuilder
    private func keyEditor(for provider: ProviderID) -> some View {
        switch provider {
        case .zai where self.model.showZAIKeyEditor:
            APIKeySettingsEditor(
                title: "Set Z.AI API key",
                instructions: "Paste your Z.AI key from the Z.AI console.",
                placeholder: "ZAI_API_KEY",
                input: self.$model.zaiAPIKeyInput,
                onCancel: { self.model.cancelZAIKeyEditor() },
                onSave: { self.model.saveZAIKey() }
            )
        case .cerebras where self.model.showCerebrasKeyEditor:
            APIKeySettingsEditor(
                title: "Set Cerebras API key",
                instructions: "Paste your API key from cloud.cerebras.ai.",
                warning: "Uses about 10K tokens per day to fetch quota because Cerebras has no dedicated usage API.",
                placeholder: "CEREBRAS_API_KEY",
                input: self.$model.cerebrasAPIKeyInput,
                onCancel: { self.model.cancelCerebrasKeyEditor() },
                onSave: { self.model.saveCerebrasKey() }
            )
        case .kimi where self.model.showKimiKeyEditor:
            APIKeySettingsEditor(
                title: "Set Kimi Code API key",
                instructions: "Paste your Kimi Code key from kimi.com/code/console.",
                placeholder: "KIMI_API_KEY",
                input: self.$model.kimiAPIKeyInput,
                onCancel: { self.model.cancelKimiKeyEditor() },
                onSave: { self.model.saveKimiKey() }
            )
        case .minimax where self.model.showMinimaxKeyEditor:
            APIKeySettingsEditor(
                title: "Set Minimax API key",
                instructions: "Paste your Coding Plan key from platform.minimax.io.",
                placeholder: "MINIMAX_KEY",
                input: self.$model.minimaxAPIKeyInput,
                onCancel: { self.model.cancelMinimaxKeyEditor() },
                onSave: { self.model.saveMinimaxKey() }
            )
        case .qwenCloud where self.model.showQwenCloudKeyEditor:
            APIKeySettingsEditor(
                title: "Set QwenCloud Individual API key",
                instructions: "Paste the sk-sp-* key from your Token Plan Individual subscription.",
                warning: "The key is validated with a free models request. QwenCloud does not expose 5-hour and 7-day usage through API-key authentication.",
                placeholder: "sk-sp-…",
                input: self.$model.qwenCloudAPIKeyInput,
                error: self.model.qwenCloudAPIKeyError,
                onCancel: { self.model.cancelQwenCloudKeyEditor() },
                onSave: { self.model.saveQwenCloudKey() }
            )
        default:
            EmptyView()
        }
    }
}

@MainActor
private struct OpenAIAccountsSettingsSection: View {
    @Bindable var model: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenAI accounts")
                    .font(.subheadline.weight(.semibold))
                Text("The first account uses your default Codex login. Additional accounts are stored separately by AI Usage Monitor.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(self.model.openAIAccounts) { account in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Toggle("", isOn: Binding(
                            get: {
                                self.model.openAIAccounts.first(where: { $0.id == account.id })?.isEnabled ?? false
                            },
                            set: { self.model.setOpenAIAccountEnabled(id: account.id, enabled: $0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        TextField(
                            "Account name",
                            text: Binding(
                                get: { self.model.openAIAccountNameInputs[account.id] ?? account.name },
                                set: { self.model.openAIAccountNameInputs[account.id] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                        Button("Save") {
                            self.model.saveOpenAIAccountName(id: account.id)
                        }
                        .controlSize(.small)

                        Button(self.loginButtonTitle(for: account)) {
                            if self.model.openAIAccountLoginStates[account.id] == .authorizing {
                                self.model.cancelOpenAIAccountLogin(id: account.id)
                            } else {
                                self.model.loginOpenAIAccount(id: account.id)
                            }
                        }
                        .controlSize(.small)

                        if !account.isDefault {
                            Button(role: .destructive) {
                                self.model.removeOpenAIAccount(id: account.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .controlSize(.small)
                            .accessibilityLabel("Remove \(account.name)")
                            .help("Remove account and its saved login")
                        }
                    }

                    HStack(spacing: 6) {
                        Text(account.isDefault ? "Default Codex path" : "Managed auth folder")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        self.loginStatus(for: account)
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
            }

            HStack(spacing: 6) {
                TextField("New account name", text: self.$model.newOpenAIAccountName)
                    .textFieldStyle(.roundedBorder)
                Button("Add account") {
                    self.model.addOpenAIAccount()
                }
                .controlSize(.small)
            }

            if let error = self.model.openAIAccountError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private func loginButtonTitle(for account: OpenAIAccountProfile) -> String {
        if self.model.openAIAccountLoginStates[account.id] == .authorizing {
            return "Cancel"
        }
        if !self.model.isOpenAIAccountAuthenticated(account) {
            return "Login"
        }
        if let error = self.model.openAIAccountResult(for: account.id)?.errorState,
           error == .authNeeded || error == .tokenExpired {
            return "Login again"
        }
        return "Reconnect"
    }

    @ViewBuilder
    private func loginStatus(for account: OpenAIAccountProfile) -> some View {
        switch self.model.openAIAccountLoginStates[account.id] ?? .idle {
        case .authorizing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Waiting for browser login…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(2)
        case .idle:
            if let error = self.model.openAIAccountResult(for: account.id)?.errorState,
               error == .authNeeded || error == .tokenExpired {
                Text("Login required")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if self.model.isOpenAIAccountAuthenticated(account) {
                Text("Connected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not connected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProviderSettingsRow: View {
    let provider: ProviderID
    @Binding var isEnabled: Bool
    let claudeKeychainEnabled: Bool
    let onClaudeKeychainAccess: () -> Void
    let onSetKey: () -> Void
    let onRemoveKey: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle(isOn: self.$isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.provider.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Text(self.providerDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Spacer(minLength: 8)

            self.configurationControls
        }
    }

    @ViewBuilder
    private var configurationControls: some View {
        switch self.provider {
        case .claude:
            Button(self.claudeKeychainEnabled ? "Authorize keychain" : "Allow keychain") {
                self.onClaudeKeychainAccess()
            }
            .controlSize(.small)
        case .zai, .cerebras, .kimi, .minimax, .qwenCloud:
            HStack(spacing: 4) {
                Button("Set key") {
                    self.onSetKey()
                }
                .controlSize(.small)

                Button(role: .destructive) {
                    self.onRemoveKey()
                } label: {
                    Image(systemName: "trash")
                }
                .controlSize(.small)
                .accessibilityLabel("Remove \(self.provider.rawValue) key")
                .help("Remove saved key")
            }
        case .codex, .gemini, .cursor:
            EmptyView()
        }
    }

    private var providerDescription: String {
        switch self.provider {
        case .claude:
            return "Uses Claude Code credentials with explicit keychain access."
        case .codex:
            return "Uses the local Codex login."
        case .gemini:
            return "Uses the local Gemini login."
        case .zai:
            return "Uses a Z.AI API key."
        case .cerebras:
            return "Uses a Cerebras API key."
        case .kimi:
            return "Uses a Kimi Code API key."
        case .minimax:
            return "Uses a Minimax Coding Plan key."
        case .qwenCloud:
            return "Uses a Token Plan Individual sk-sp-* key."
        case .cursor:
            return "Uses the signed-in Cursor app session."
        }
    }
}

private struct APIKeySettingsEditor: View {
    let title: String
    let instructions: String
    var warning: String?
    let placeholder: String
    @Binding var input: String
    var error: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(self.title)
                .font(.caption.weight(.semibold))
            Text(self.instructions)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let warning = self.warning {
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            SecureField(self.placeholder, text: self.$input)
                .textFieldStyle(.roundedBorder)
            if let error = self.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Cancel") {
                    self.onCancel()
                }
                Spacer()
                Button("Save") {
                    self.onSave()
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
private struct UpdateSettingsSection: View {
    @Bindable var model: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updates")
                        .font(.headline)
                    Text(self.statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if self.model.showsManualUpdateCheck {
                    Button("Check Updates") {
                        self.model.checkForUpdates()
                    }
                    .controlSize(.small)
                }
            }

            if let version = self.model.updateAvailableVersion {
                Button {
                    self.model.triggerUpdate()
                } label: {
                    Label("Download & Restart (\(version))", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if self.model.updateStatus == .downloading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading update…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if case .error(let message) = self.model.updateStatus {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusText: String {
        switch self.model.updateStatus {
        case .unknown:
            return "Checks GitHub Releases for a newer version."
        case .upToDate:
            return "AI Usage Monitor is up to date."
        case .available(let version, _):
            return "Version \(version) is available."
        case .downloading:
            return "Preparing the latest version."
        case .readyToInstall:
            return "The update is ready to install."
        case .error:
            return "The last update attempt failed."
        }
    }
}
