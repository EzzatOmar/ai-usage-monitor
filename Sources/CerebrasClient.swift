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

    /// Calls GET /v1/models (lightweight, no token cost) and reads rate-limit headers.
    static func fetchRateLimits(apiKey: String) async throws -> RateLimitResult {
        var request = URLRequest(url: URL(string: "https://api.cerebras.ai/v1/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderErrorState.endpointError("Invalid Cerebras response")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ProviderErrorState.tokenExpired
            }
            throw ProviderErrorState.endpointError("HTTP \(http.statusCode)")
        }

        return Self.parseRateLimitHeaders(http, now: Date())
    }

    /// Parses `x-ratelimit-*` headers from any Cerebras API response.
    static func parseRateLimitHeaders(_ http: HTTPURLResponse, now: Date) -> RateLimitResult {
        let headers = http.allHeaderFields

        // Daily request limits (primary window)
        let dailyLimit = Self.doubleHeader(headers, "x-ratelimit-limit-requests-day")
        let dailyRemaining = Self.doubleHeader(headers, "x-ratelimit-remaining-requests-day")
        let dailyResetSecs = Self.doubleHeader(headers, "x-ratelimit-reset-requests-day")

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

        // Per-minute token limits (secondary window)
        let minuteLimit = Self.doubleHeader(headers, "x-ratelimit-limit-tokens-minute")
        let minuteRemaining = Self.doubleHeader(headers, "x-ratelimit-remaining-tokens-minute")
        let minuteResetSecs = Self.doubleHeader(headers, "x-ratelimit-reset-tokens-minute")

        var secondaryWindow: UsageWindow?
        if let limit = minuteLimit, let remaining = minuteRemaining, limit > 0 {
            let usedPercent = ((limit - remaining) / limit) * 100
            let resetAt = minuteResetSecs.map { now.addingTimeInterval($0) }
            secondaryWindow = UsageWindow(
                usedPercent: max(0, min(100, usedPercent)),
                resetAt: resetAt,
                windowSeconds: 60
            )
        }

        // Build account label from raw numbers
        var label: String?
        if let limit = dailyLimit, let remaining = dailyRemaining {
            let used = Int(limit - remaining)
            let total = Int(limit)
            label = "Day: \(used)/\(total) reqs"
        }

        return RateLimitResult(primary: primaryWindow, secondary: secondaryWindow, accountLabel: label)
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
