import SwiftUI

struct MenuBarRootView: View {
    @Bindable var model: MenuBarViewModel
    let onOpenSettings: () -> Void

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

            if self.model.activeUsageRows.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No providers enabled")
                        .font(.subheadline.weight(.semibold))
                    Text("Open Settings to choose providers to monitor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(self.model.activeUsageRows) { row in
                    ProviderRow(
                        result: row.result,
                        provider: row.provider,
                        title: row.title
                    )
                }
            }

            Divider()

            HStack(spacing: 8) {
                Text("Updated \(RelativeTimeFormatter.lastUpdatedText(self.model.snapshot.lastUpdated))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Link(destination: URL(string: "https://github.com/EzzatOmar/ai-usage-monitor")!) {
                    Image(systemName: "star")
                }
                .accessibilityLabel("Star on GitHub")
                .help("Star on GitHub")

                Button {
                    self.onOpenSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .help("Settings")

                Button {
                    self.model.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(self.model.snapshot.isRefreshing)
                .accessibilityLabel("Refresh now")
                .help("Refresh now")

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 340)
    }
}

private struct ProviderRow: View {
    let result: ProviderUsageResult?
    let provider: ProviderID
    let title: String
    @State private var showingErrorDetails = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(self.title)
                    .font(.subheadline.weight(.semibold))

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

            if let badge = self.result?.errorState?.badgeText {
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.12), in: Capsule())
                    .foregroundStyle(.red)
            }
        }
    }

    private func inlineErrorDetail(for rawDetail: String) -> String {
        if self.provider == .claude, self.result?.errorState == .authNeeded {
            return "Authorize access to Claude Code credentials in Settings"
        }
        if self.provider == .claude, self.result?.errorState == .tokenExpired {
            return "Run 'claude auth login', then authorize keychain in Settings"
        }
        if self.provider == .codex, self.result?.errorState == .authNeeded {
            return "Open Settings and log in to this OpenAI account"
        }
        if self.provider == .codex, self.result?.errorState == .tokenExpired {
            return "OpenAI login expired; reconnect this account in Settings"
        }
        if self.provider == .cursor, self.result?.errorState == .authNeeded {
            return "Sign into the Cursor app"
        }
        if self.provider == .cursor, self.result?.errorState == .tokenExpired {
            return "Cursor session expired; sign into Cursor again"
        }
        if self.result?.errorState == .authNeeded,
           [.zai, .cerebras, .kimi, .minimax, .qwenCloud].contains(self.provider) {
            return "Add the provider API key in Settings"
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
