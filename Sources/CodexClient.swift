import Foundation

struct CodexClient: ProviderClient {
    let providerID: ProviderID = .codex
    let account: OpenAIAccountProfile

    init(account: OpenAIAccountProfile = .defaultAccount()) {
        self.account = account
    }

    var clientID: ProviderClientID {
        ProviderClientID(provider: .codex, accountID: self.account.id)
    }

    func fetchUsage(now: Date, mode _: UsageRefreshMode) async -> ProviderUsageResult {
        do {
            guard let stored = try OpenAIAuthFileStore.loadCredential(at: self.account.authURL()) else {
                throw ProviderErrorState.authNeeded
            }

            let usageURL = Self.resolveUsageURL(configURL: self.account.configURL())
            let response: UsageResponse
            switch stored {
            case .apiKey(let apiKey):
                response = try await Self.fetchUsage(
                    accessToken: apiKey,
                    accountID: nil,
                    usageURL: usageURL
                )
            case .oauth(let initialCredentials):
                var credentials = initialCredentials
                var refreshed = false
                if credentials.needsRefresh {
                    credentials = try await Self.refresh(credentials, authURL: self.account.authURL())
                    refreshed = true
                }
                do {
                    response = try await Self.fetchUsage(
                        accessToken: credentials.accessToken,
                        accountID: credentials.accountID,
                        usageURL: usageURL
                    )
                } catch let error as ProviderErrorState where error == .tokenExpired && !refreshed {
                    credentials = try await Self.refresh(credentials, authURL: self.account.authURL())
                    response = try await Self.fetchUsage(
                        accessToken: credentials.accessToken,
                        accountID: credentials.accountID,
                        usageURL: usageURL
                    )
                }
            }

            return ProviderUsageResult(
                provider: .codex,
                accountID: self.account.id,
                primaryWindow: response.rateLimit.primaryWindow?.usageWindow,
                secondaryWindow: response.rateLimit.secondaryWindow?.usageWindow,
                accountLabel: response.planType,
                lastUpdated: now
            )
        } catch let error as ProviderErrorState {
            return self.errorResult(error, now: now)
        } catch {
            return self.errorResult(.networkError(error.localizedDescription), now: now)
        }
    }

    private func errorResult(_ error: ProviderErrorState, now: Date) -> ProviderUsageResult {
        ProviderUsageResult(
            provider: .codex,
            accountID: self.account.id,
            lastUpdated: now,
            errorState: error
        )
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

    private static func refresh(
        _ credentials: OpenAIOAuthCredentials,
        authURL: URL
    ) async throws -> OpenAIOAuthCredentials {
        if case .oauth(let latest)? = try OpenAIAuthFileStore.loadCredential(at: authURL),
           latest.refreshToken != credentials.refreshToken {
            return latest
        }

        let url = URL(string: "https://auth.openai.com/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AIUsageMonitor", forHTTPHeaderField: "User-Agent")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderErrorState.endpointError("Invalid OpenAI refresh response")
        }
        if [400, 401, 403].contains(http.statusCode),
           case .oauth(let latest)? = try? OpenAIAuthFileStore.loadCredential(at: authURL),
           latest.refreshToken != credentials.refreshToken {
            return latest
        }
        guard http.statusCode == 200 else {
            throw Self.refreshFailure(
                statusCode: http.statusCode,
                retryAfter: http.retryAfterTimeInterval
            )
        }
        guard let decoded = try? JSONDecoder().decode(OpenAITokenResponse.self, from: data),
              !decoded.accessToken.isEmpty
        else {
            throw ProviderErrorState.parseError("Invalid OpenAI refresh payload")
        }
        return try OpenAIAuthFileStore.persistRefreshedOAuth(
            decoded,
            replacing: credentials,
            at: authURL
        )
    }

    static func refreshFailure(
        statusCode: Int,
        retryAfter: TimeInterval?
    ) -> ProviderErrorState {
        if statusCode == 429 {
            return .rateLimited(
                "OpenAI authentication is rate limited",
                retryAfter: retryAfter
            )
        }
        if [400, 401, 403].contains(statusCode) {
            return .tokenExpired
        }
        return .endpointError("OpenAI refresh failed (HTTP \(statusCode))")
    }

    private static func fetchUsage(
        accessToken: String,
        accountID: String?,
        usageURL: URL
    ) async throws -> UsageResponse {
        var request = URLRequest(url: usageURL)
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
        case 429:
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = body.isEmpty ? "HTTP 429" : "HTTP 429: \(body)"
            throw ProviderErrorState.rateLimited(message, retryAfter: http.retryAfterTimeInterval)
        case 401, 403:
            throw ProviderErrorState.tokenExpired
        default:
            throw ProviderErrorState.endpointError("HTTP \(http.statusCode)")
        }
    }

    private static func resolveUsageURL(configURL: URL = LocalPaths.codexConfigPath()) -> URL {
        let defaultBase = "https://chatgpt.com/backend-api"
        let configBase = Self.readChatGPTBaseURLFromConfig(at: configURL) ?? defaultBase
        var base = configBase
        while base.hasSuffix("/") {
            base.removeLast()
        }
        if base.contains("/backend-api") {
            return URL(string: base + "/wham/usage")!
        }
        return URL(string: base + "/api/codex/usage")!
    }

    private static func readChatGPTBaseURLFromConfig(at configURL: URL) -> String? {
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

}

#if DEBUG
extension CodexClient {
    static func decodeUsageResponse(_ data: Data) throws -> (Double, Double?) {
        let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
        return (usage.rateLimit.primaryWindow?.usedPercent ?? 0, usage.rateLimit.secondaryWindow?.usedPercent)
    }

    static func extractAccountIDForTests(_ token: String) -> String? {
        OpenAIAuthFileStore.extractAccountID(fromJWT: token)
    }

}
#endif
