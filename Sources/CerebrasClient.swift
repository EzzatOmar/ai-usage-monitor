import Foundation

struct CerebrasClient: ProviderClient {
    let providerID: ProviderID = .cerebras

    func fetchUsage(now: Date) async -> ProviderUsageResult {
        guard let apiKey = Self.loadAPIKey() else {
            return ProviderUsageResult(
                provider: .cerebras,
                primaryWindow: nil,
                secondaryWindow: nil,
                accountLabel: nil,
                lastUpdated: now,
                errorState: .authNeeded,
                isStale: false
            )
        }

        do {
            let usage = try await Self.fetchRateLimits(apiKey: apiKey)
            return ProviderUsageResult(
                provider: .cerebras,
                primaryWindow: usage.primary,
                secondaryWindow: usage.secondary,
                accountLabel: usage.accountLabel,
                lastUpdated: now,
                errorState: nil,
                isStale: false
            )
        } catch let error as ProviderErrorState {
            return ProviderUsageResult(
                provider: .cerebras,
                primaryWindow: nil,
                secondaryWindow: nil,
                accountLabel: nil,
                lastUpdated: now,
                errorState: error,
                isStale: false
            )
        } catch {
            return ProviderUsageResult(
                provider: .cerebras,
                primaryWindow: nil,
                secondaryWindow: nil,
                accountLabel: nil,
                lastUpdated: now,
                errorState: .networkError(error.localizedDescription),
                isStale: false
            )
        }
    }

    struct RateLimitResult {
        let primary: UsageWindow?
        let secondary: UsageWindow?
        let accountLabel: String?
    }

    private static func loadAPIKey() -> String? {
        if let stored = AuthStore.loadCerebrasAPIKey(), !stored.isEmpty {
            return stored
        }
        let env = ProcessInfo.processInfo.environment
        for keyName in ["CEREBRAS_API_KEY"] {
            if let key = env[keyName]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                return key
            }
        }
        return nil
    }

    static func fetchRateLimits(apiKey: String) async throws -> RateLimitResult {
        var request = URLRequest(url: URL(string: "https://api.cerebras.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "zai-glm-4.7",
            "messages": [["role": "user", "content": "hi"]],
            "max_completion_tokens": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderErrorState.endpointError("Invalid Cerebras response")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ProviderErrorState.tokenExpired
            }
            if http.statusCode == 402 {
                throw ProviderErrorState.endpointError("Add payment method in Cerebras dashboard")
            }
            throw ProviderErrorState.endpointError("HTTP \(http.statusCode)")
        }

        return Self.parseRateLimitHeaders(http, now: Date())
    }

    /// Parses `x-ratelimit-*` headers from any Cerebras API response.
    static func parseRateLimitHeaders(_ http: HTTPURLResponse, now: Date) -> RateLimitResult {
        let headers = http.allHeaderFields

        // Daily token limits (primary window) - no weekly limit available
        let dailyLimit = Self.doubleHeader(headers, "x-ratelimit-limit-tokens-day")
        let dailyRemaining = Self.doubleHeader(headers, "x-ratelimit-remaining-tokens-day")
        let dailyResetSecs = Self.doubleHeader(headers, "x-ratelimit-reset-tokens-day")

        var primaryWindow: UsageWindow?
        if let limit = dailyLimit, let remaining = dailyRemaining, limit > 0 {
            let usedPercent = ((limit - remaining) / limit) * 100
            let resetAt = dailyResetSecs.map { now.addingTimeInterval($0) }
            primaryWindow = UsageWindow(
                usedPercent: max(0, min(100, usedPercent)),
                resetAt: resetAt,
                windowSeconds: 86400
            )
        }

        var label: String?
        if let limit = dailyLimit, let remaining = dailyRemaining {
            let used = Int(limit - remaining)
            let total = Int(limit)
            label = "Day: \(used)/\(total) tokens"
        }

        return RateLimitResult(primary: primaryWindow, secondary: nil, accountLabel: label)
    }

    private static func doubleHeader(_ headers: [AnyHashable: Any], _ name: String) -> Double? {
        // HTTP headers are case-insensitive; try exact and lowercased lookup
        if let value = headers[name] as? String, let d = Double(value) {
            return d
        }
        if let value = headers[name.lowercased()] as? String, let d = Double(value) {
            return d
        }
        // Iterate for case-insensitive match
        for (key, val) in headers {
            if let k = key as? String, k.lowercased() == name.lowercased(),
               let v = val as? String, let d = Double(v)
            {
                return d
            }
        }
        return nil
    }
}
