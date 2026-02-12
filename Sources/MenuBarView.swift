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
                ProviderRow(result: self.model.snapshot.results.first(where: { $0.provider == provider }), provider: provider)
            }

            Divider()

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
}
