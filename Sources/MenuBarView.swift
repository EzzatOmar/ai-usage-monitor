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
            }

            HStack {
                Link(destination: URL(string: "https://github.com/EzzatOmar/ai-usage-monitor")!) {
                    Label("Star on GitHub", systemImage: "star")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                Spacer()
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
    let onClaudeKeychainAccess: () -> Void
    let claudeKeychainEnabled: Bool
    let onZAISetup: () -> Void
    let onCerebrasSetup: () -> Void
    let onKimiSetup: () -> Void
    let onMinimaxSetup: () -> Void
    let onRemoveAuth: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
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
                            Text("\(Int(primary.remainingPercent.rounded()))% left - \(RelativeTimeFormatter.resetText(primary.resetAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No quota data")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let secondary = result.secondaryWindow {
                            Text("Weekly: \(Int(secondary.remainingPercent.rounded()))% left - \(RelativeTimeFormatter.resetText(secondary.resetAt))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let errorDetail = result.errorState?.detailText {
                        Text(errorDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
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

                    if self.provider == .claude, self.result?.errorState != nil, !self.claudeKeychainEnabled {
                        Button("Allow keychain") {
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
                }

                if !self.isEnabled {
                    Button("Remove auth") {
                        self.onRemoveAuth()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.blue.opacity(0.75))
                }
            }
        }
    }
}
