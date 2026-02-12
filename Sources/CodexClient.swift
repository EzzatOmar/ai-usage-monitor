import Foundation

struct CodexClient: ProviderClient {
    let providerID: ProviderID = .codex

    func fetchUsage(now: Date) async -> ProviderUsageResult {
        do {
            var credentials = try Self.loadCredentials()
            if credentials.needsRefresh, !credentials.refreshToken.isEmpty {
                credentials = try await Self.refresh(credentials)
            }
            let response = try await Self.fetchUsage(accessToken: credentials.accessToken, accountID: credentials.accountID)
            return ProviderUsageResult(
                provider: .codex,
                primaryWindow: response.rateLimit.primaryWindow?.usageWindow,
                secondaryWindow: response.rateLimit.secondaryWindow?.usageWindow,
                accountLabel: response.planType,
                lastUpdated: now,
                errorState: nil,
                isStale: false
            )
        } catch let error as ProviderErrorState {
            return ProviderUsageResult(provider: .codex, primaryWindow: nil, secondaryWindow: nil, accountLabel: nil, lastUpdated: now, errorState: error, isStale: false)
        } catch {
            return ProviderUsageResult(provider: .codex, primaryWindow: nil, secondaryWindow: nil, accountLabel: nil, lastUpdated: now, errorState: .networkError(error.localizedDescription), isStale: false)
        }
    }

    private struct Credentials {
        let accessToken: String
        let refreshToken: String
        let accountID: String?
        let lastRefresh: Date?

        var needsRefresh: Bool {
            guard let lastRefresh else { return true }
            return Date().timeIntervalSince(lastRefresh) > (8 * 24 * 60 * 60)
        }
    }

    private struct UsageResponse: Decodable {
        let planType: String?
        let rateLimit: RateLimit

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
        }
    }

    private struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    private struct Window: Decodable {
        let usedPercent: Double
        let resetAt: Int?
        let limitWindowSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }

        var usageWindow: UsageWindow {
            UsageWindow(
                usedPercent: self.usedPercent,
                resetAt: self.resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                windowSeconds: self.limitWindowSeconds
            )
        }
    }

    private struct RefreshResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
        }
    }

    private static func loadCredentials() throws -> Credentials {
        let url = LocalPaths.codexAuthPath()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProviderErrorState.authNeeded
        }
        let json = try JSONFile.readDictionary(at: url)
        if let apiKey = json["OPENAI_API_KEY"] as? String, !apiKey.isEmpty {
            return Credentials(accessToken: apiKey, refreshToken: "", accountID: nil, lastRefresh: nil)
        }
        guard let tokens = json["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String,
              let refresh = tokens["refresh_token"] as? String,
              !access.isEmpty
        else {
            throw ProviderErrorState.authNeeded
        }
        let accountID = tokens["account_id"] as? String
        let lastRefresh = Self.parseISO8601(json["last_refresh"] as? String)
        return Credentials(accessToken: access, refreshToken: refresh, accountID: accountID, lastRefresh: lastRefresh)
    }

    private static func refresh(_ credentials: Credentials) async throws -> Credentials {
        guard let url = URL(string: "https://auth.openai.com/oauth/token") else {
            throw ProviderErrorState.endpointError("Invalid refresh endpoint")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "scope": "openid profile email",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderErrorState.endpointError("Invalid refresh response")
        }
        if http.statusCode == 401 {
            throw ProviderErrorState.tokenExpired
        }
        guard http.statusCode == 200 else {
            throw ProviderErrorState.endpointError("Refresh failed (\(http.statusCode))")
        }
        guard let decoded = try? JSONDecoder().decode(RefreshResponse.self, from: data) else {
            throw ProviderErrorState.parseError("Invalid refresh payload")
        }
        return Credentials(
            accessToken: decoded.accessToken ?? credentials.accessToken,
            refreshToken: decoded.refreshToken ?? credentials.refreshToken,
            accountID: credentials.accountID,
            lastRefresh: Date()
        )
    }

    private static func fetchUsage(accessToken: String, accountID: String?) async throws -> UsageResponse {
        var request = URLRequest(url: Self.resolveUsageURL())
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AIUsageMonitor", forHTTPHeaderField: "User-Agent")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderErrorState.endpointError("Invalid usage response")
        }
        switch http.statusCode {
        case 200...299:
            guard let decoded = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
                throw ProviderErrorState.parseError("Invalid usage payload")
            }
            return decoded
        case 401, 403:
            throw ProviderErrorState.tokenExpired
        default:
            throw ProviderErrorState.endpointError("HTTP \(http.statusCode)")
        }
    }

    private static func resolveUsageURL() -> URL {
        let defaultBase = "https://chatgpt.com/backend-api"
        let configBase = Self.readChatGPTBaseURLFromConfig() ?? defaultBase
        var base = configBase
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if base.contains("/backend-api") {
            return URL(string: base + "/wham/usage")!
        }
        return URL(string: base + "/api/codex/usage")!
    }

    private static func readChatGPTBaseURLFromConfig() -> String? {
        let configURL = LocalPaths.codexConfigPath()
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("chatgpt_base_url") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            value = value.replacingOccurrences(of: "\"", with: "")
            value = value.replacingOccurrences(of: "'", with: "")
            return value
        }
        return nil
    }

    private static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

#if DEBUG
extension CodexClient {
    static func decodeUsageResponse(_ data: Data) throws -> (Double, Double?) {
        let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
        return (usage.rateLimit.primaryWindow?.usedPercent ?? 0, usage.rateLimit.secondaryWindow?.usedPercent)
    }
}
#endif
