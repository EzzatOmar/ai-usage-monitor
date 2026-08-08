import SwiftUI

struct MenuBarRootView: View {
    @Bindable var model: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI Usage Monitor")
                    .font(.headline)
                Spacer()
                if self.model.snapshot.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ForEach(ProviderID.allCases, id: \.self) { provider in
                ProviderRow(
                    result: self.model.snapshot.results.first(where: { $0.provider == provider }),
                    provider: provider,
                    isEnabled: Binding(
                        get: { self.model.isProviderEnabled(provider) },
                        set: { self.model.setProviderEnabled(provider, $0) }
                    ),
                    onClaudeKeychainAccess: { self.model.enableClaudeKeychainAccess() },
                    claudeKeychainEnabled: self.model.claudeKeychainEnabled,
                    onZAISetup: { self.model.openZAIKeyEditor() },
                    onCerebrasSetup: { self.model.openCerebrasKeyEditor() },
                    onKimiSetup: { self.model.openKimiKeyEditor() },
                    onMinimaxSetup: { self.model.openMinimaxKeyEditor() },
                    onQwenCloudKeySetup: { self.model.openQwenCloudKeyEditor() },
                    onRemoveAuth: { self.model.clearAuth(for: provider) }
                )
            }

            Divider()

            if self.model.showZAIKeyEditor {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set Z.AI API key")
                        .font(.caption.weight(.semibold))
                    Text("Paste your Z.AI key from the Z.AI console.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    SecureField("ZAI_API_KEY", text: self.$model.zaiAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel") { self.model.cancelZAIKeyEditor() }
                        Spacer()
                        Button("Save") { self.model.saveZAIKey() }
                    }
                }
            }

            if self.model.showCerebrasKeyEditor {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set Cerebras API key")
                        .font(.caption.weight(.semibold))
                    Text("Paste your API key from cloud.cerebras.ai.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Note: Uses ~10K tokens/day to fetch quota (no dedicated usage API).")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    SecureField("CEREBRAS_API_KEY", text: self.$model.cerebrasAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel") { self.model.cancelCerebrasKeyEditor() }
                        Spacer()
                        Button("Save") { self.model.saveCerebrasKey() }
                    }
                }
            }

            if self.model.showMinimaxKeyEditor {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set Minimax API key")
                        .font(.caption.weight(.semibold))
                    Text("Paste your Coding Plan key from platform.minimax.io.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    SecureField("MINIMAX_KEY", text: self.$model.minimaxAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel") { self.model.cancelMinimaxKeyEditor() }
                        Spacer()
                        Button("Save") { self.model.saveMinimaxKey() }
                    }
                }
            }

            if self.model.showKimiKeyEditor {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set Kimi Code API key")
                        .font(.caption.weight(.semibold))
                    Text("Paste your Kimi Code key from kimi.com/code/console.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    SecureField("KIMI_API_KEY", text: self.$model.kimiAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel") { self.model.cancelKimiKeyEditor() }
                        Spacer()
                        Button("Save") { self.model.saveKimiKey() }
                    }
                }
            }

            if self.model.showQwenCloudKeyEditor {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set QwenCloud Individual API key")
                        .font(.caption.weight(.semibold))
                    Text("Paste the sk-sp-* key from your Token Plan Individual subscription.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("The key is validated with a free models request. QwenCloud does not expose 5-hour and 7-day usage through API-key authentication.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    SecureField("sk-sp-…", text: self.$model.qwenCloudAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                    if let error = self.model.qwenCloudAPIKeyError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Button("Cancel") { self.model.cancelQwenCloudKeyEditor() }
                        Spacer()
                        Button("Save") { self.model.saveQwenCloudKey() }
                    }
                }
            }

            HStack {
                Text("Updated \(RelativeTimeFormatter.lastUpdatedText(self.model.snapshot.lastUpdated))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh now") {
                    self.model.refreshNow()
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
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Link(destination: URL(string: "https://github.com/EzzatOmar/ai-usage-monitor")!) {
                    Label("Star on GitHub", systemImage: "star")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                Spacer()
                if self.model.showsManualUpdateCheck {
                    Button("Check Updates") {
                        self.model.checkForUpdates()
                    }
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 340)
    }
}

private struct ProviderRow: View {
    let result: ProviderUsageResult?
    let provider: ProviderID
    @Binding var isEnabled: Bool
    @State private var showingErrorDetails = false
    let onClaudeKeychainAccess: () -> Void
    let claudeKeychainEnabled: Bool
    let onZAISetup: () -> Void
    let onCerebrasSetup: () -> Void
    let onKimiSetup: () -> Void
    let onMinimaxSetup: () -> Void
    let onQwenCloudKeySetup: () -> Void
    let onRemoveAuth: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(self.provider.rawValue)
                        .font(.subheadline.weight(.semibold))
                    Toggle("", isOn: self.$isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
                if let result {
                    if !result.modelWindows.isEmpty {
                        ForEach(result.modelWindows, id: \.modelId) { item in
                            Text("\(item.modelId)    \(Int(item.window.remainingPercent.rounded()))% left - \(RelativeTimeFormatter.resetText(item.window.resetAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if let primary = result.primaryWindow {
                            Text("\(self.primaryWindowLabel)\(Int(primary.remainingPercent.rounded()))% left - \(RelativeTimeFormatter.resetText(primary.resetAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No quota data")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let secondary = result.secondaryWindow {
                            Text("\(self.secondaryWindowLabel)\(Int(secondary.remainingPercent.rounded()))% left - \(RelativeTimeFormatter.resetText(secondary.resetAt))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let accountLabel = result.accountLabel {
                        Text(accountLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let errorDetail = result.errorState?.detailText {
                        Text(self.inlineErrorDetail(for: errorDetail))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Button("Show error") {
                            self.showingErrorDetails = true
                        }
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.blue.opacity(0.85))
                        .popover(isPresented: self.$showingErrorDetails, arrowEdge: .trailing) {
                            ScrollView {
                                Text(self.fullErrorDetail(for: errorDetail))
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .frame(width: 360, alignment: .leading)
                        }
                    }

                    if result.isStale {
                        Text("Using last known data")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("Pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                if self.isEnabled, let badge = self.result?.errorState?.badgeText {
                    Text(badge)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.12), in: Capsule())
                        .foregroundStyle(.red)

                    if self.provider == .claude,
                       self.result?.errorState == .authNeeded || self.result?.errorState == .tokenExpired {
                        Button(self.claudeKeychainEnabled ? "Authorize keychain" : "Allow keychain") {
                            self.onClaudeKeychainAccess()
                        }
                        .font(.caption2)
                    }

                    if badge == "Auth needed", self.provider == .zai {
                        Button("Set key") {
                            self.onZAISetup()
                        }
                        .font(.caption2)
                    }

                    if badge == "Auth needed", self.provider == .cerebras {
                        Button("Set key") {
                            self.onCerebrasSetup()
                        }
                        .font(.caption2)
                    }

                    if badge == "Auth needed", self.provider == .minimax {
                        Button("Set key") {
                            self.onMinimaxSetup()
                        }
                        .font(.caption2)
                    }

                    if badge == "Auth needed", self.provider == .kimi {
                        Button("Set key") {
                            self.onKimiSetup()
                        }
                        .font(.caption2)
                    }

                    if self.provider == .qwenCloud {
                        Button("Set key") {
                            self.onQwenCloudKeySetup()
                        }
                        .font(.caption2)
                    }

                }

                if !self.isEnabled,
                   self.provider != .claude,
                   self.provider != .codex,
                   self.provider != .gemini,
                   self.provider != .cursor {
                    Button("Remove auth") {
                        self.onRemoveAuth()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.blue.opacity(0.75))
                }

                if self.isEnabled,
                   self.provider == .qwenCloud,
                   self.result?.errorState == nil,
                   self.result != nil {
                    Button("Remove key") {
                        self.onRemoveAuth()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.blue.opacity(0.75))
                }
            }
        }
    }

    private func inlineErrorDetail(for rawDetail: String) -> String {
        if self.provider == .claude, self.result?.errorState == .authNeeded {
            return "Authorize access to Claude Code credentials"
        }
        if self.provider == .claude, self.result?.errorState == .tokenExpired {
            return "Run 'claude auth login', then authorize keychain again"
        }
        if self.provider == .codex, self.result?.errorState == .authNeeded {
            return "Run 'codex login' in terminal"
        }
        if self.provider == .cursor, self.result?.errorState == .authNeeded {
            return "Sign into the Cursor app"
        }
        if self.provider == .cursor, self.result?.errorState == .tokenExpired {
            return "Cursor session expired; sign into Cursor again"
        }
        return rawDetail
    }

    private var primaryWindowLabel: String {
        switch self.provider {
        case .qwenCloud:
            return "5h: "
        case .cursor:
            return "API: "
        default:
            return ""
        }
    }

    private var secondaryWindowLabel: String {
        self.provider == .cursor ? "Auto/Composer: " : "Weekly: "
    }

    private func fullErrorDetail(for rawDetail: String) -> String {
        self.inlineErrorDetail(for: rawDetail)
    }
}
