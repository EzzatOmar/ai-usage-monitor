import Foundation

struct ZAIClient: ProviderClient {
    let providerID: ProviderID = .zai

    func fetchUsage(now: Date) async -> ProviderUsageResult {
        let env = ProcessInfo.processInfo.environment
        let apiKey = env["ZAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !apiKey.isEmpty else {
            return ProviderUsageResult(
                provider: .zai,
                primaryWindow: nil,
                secondaryWindow: nil,
                accountLabel: nil,
                lastUpdated: now,
                errorState: .authNeeded,
                isStale: false
            )
        }

        return ProviderUsageResult(
            provider: .zai,
            primaryWindow: nil,
            secondaryWindow: nil,
            accountLabel: "API key configured",
            lastUpdated: now,
            errorState: nil,
            isStale: false
        )
    }
}
