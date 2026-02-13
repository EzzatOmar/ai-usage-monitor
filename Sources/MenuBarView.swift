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
                    onClaudeSetup: { self.model.openClaudeTokenEditor() },
                    onClaudeKeychainAccess: { self.model.enableClaudeKeychainAccess() },
                    claudeKeychainEnabled: self.model.claudeKeychainEnabled,
                    onZAISetup: { self.model.openZAIKeyEditor() },
                    onCerebrasSetup: { self.model.openCerebrasKeyEditor() }
                )
            }

            Divider()

            if self.model.showClaudeTokenEditor {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude setup token")
                        .font(.caption.weight(.semibold))
                    Text("Run `claude setup-token`, then paste the token here.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    SecureField("setup-token", text: self.$model.claudeSetupTokenInput)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel") { self.model.cancelClaudeTokenEditor() }
                        Spacer()
                        Button("Save") { self.model.saveClaudeToken() }
                    }
                }
            }

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
                    SecureField("CEREBRAS_API_KEY", text: self.$model.cerebrasAPIKeyInput)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel") { self.model.cancelCerebrasKeyEditor() }
                        Spacer()
                        Button("Save") { self.model.saveCerebrasKey() }
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
        }
        .padding(12)
        .frame(width: 340)
    }
}

private struct ProviderRow: View {
    let result: ProviderUsageResult?
    let provider: ProviderID
    let onClaudeSetup: () -> Void
    let onClaudeKeychainAccess: () -> Void
    let claudeKeychainEnabled: Bool
    let onZAISetup: () -> Void
    let onCerebrasSetup: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(self.provider.rawValue)
                    .font(.subheadline.weight(.semibold))
                if let result {
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

            if let badge = self.result?.errorState?.badgeText {
                VStack(alignment: .trailing, spacing: 5) {
                    Text(badge)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.12), in: Capsule())
                        .foregroundStyle(.red)

                    if self.provider == .claude, self.result?.errorState != nil {
                        HStack(spacing: 8) {
                            Button("Paste token") {
                                self.onClaudeSetup()
                            }
                            .font(.caption2)

                            if !self.claudeKeychainEnabled {
                                Button("Allow keychain") {
                                    self.onClaudeKeychainAccess()
                                }
                                .font(.caption2)
                            }
                        }
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
                }
            }
        }
    }
}
