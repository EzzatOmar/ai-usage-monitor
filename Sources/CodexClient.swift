import Foundation

struct CodexClient: ProviderClient {
    let providerID: ProviderID = .codex

    func fetchUsage(now: Date, mode _: UsageRefreshMode) async -> ProviderUsageResult {
        do {
            let credentialsList = try Self.loadCredentials()
            var lastAuthError: ProviderErrorState?

            for candidate in credentialsList {
                var credentials = candidate.credentials
                do {
                    if credentials.needsRefresh {
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
                    if Self.shouldTryNextCredential(after: error) {
                        lastAuthError = error
                        continue
                    }
                    throw error
                }
            }

            throw lastAuthError ?? ProviderErrorState.authNeeded
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
        let expiresAt: Date?

        var needsRefresh: Bool {
            guard !self.refreshToken.isEmpty else { return false }
            if let expiresAt {
                return Date().addingTimeInterval(60) >= expiresAt
            }
            guard let lastRefresh else { return true }
            return Date().timeIntervalSince(lastRefresh) > (8 * 24 * 60 * 60)
        }
    }

    private enum CredentialSource {
        case codexAPIKey
        case codexOAuth
        case openCodeOAuth
    }

    private struct CredentialCandidate {
        let credentials: Credentials
        let source: CredentialSource
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
        let expiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case expiresIn = "expires_in"
        }
    }

    private struct OpenCodeOAuth: Decodable {
        let type: String
        let refresh: String
        let access: String
        let expires: Double?
        let accountId: String?
    }

    private struct JWTClaims: Decodable {
        let chatgptAccountID: String?
        let organizations: [Organization]?
        let openAIAuth: OpenAIAuth?

        struct Organization: Decodable {
            let id: String?
        }

        struct OpenAIAuth: Decodable {
            let chatgptAccountID: String?

            enum CodingKeys: String, CodingKey {
                case chatgptAccountID = "chatgpt_account_id"
            }
        }

        enum CodingKeys: String, CodingKey {
            case chatgptAccountID = "chatgpt_account_id"
            case organizations
            case openAIAuth = "https://api.openai.com/auth"
        }
    }

    private static func loadCredentials() throws -> [CredentialCandidate] {
        var candidates: [CredentialCandidate] = []
        candidates.append(contentsOf: try Self.loadCodexCredentials())
        if let credentials = try Self.loadOpenCodeCredentials() {
            candidates.append(CredentialCandidate(credentials: credentials, source: .openCodeOAuth))
        }
        guard !candidates.isEmpty else {
            throw ProviderErrorState.authNeeded
        }
        return candidates
    }

    private static func loadCodexCredentials() throws -> [CredentialCandidate] {
        let url = LocalPaths.codexAuthPath()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let json = try JSONFile.readDictionary(at: url)
        var candidates: [CredentialCandidate] = []

        if let apiKey = json["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            candidates.append(CredentialCandidate(
                credentials: Credentials(accessToken: apiKey, refreshToken: "", accountID: nil, lastRefresh: nil, expiresAt: nil),
                source: .codexAPIKey
            ))
        }

        if let tokens = json["tokens"] as? [String: Any],
           let access = tokens["access_token"] as? String,
           let refresh = tokens["refresh_token"] as? String,
           !access.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !refresh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let accountID = (tokens["account_id"] as? String)
                ?? Self.extractAccountID(fromJWT: tokens["id_token"] as? String)
                ?? Self.extractAccountID(fromJWT: access)
            let lastRefresh = Self.parseISO8601(json["last_refresh"] as? String)
            candidates.append(CredentialCandidate(
                credentials: Credentials(accessToken: access, refreshToken: refresh, accountID: accountID, lastRefresh: lastRefresh, expiresAt: nil),
                source: .codexOAuth
            ))
        }

        return candidates
    }

    private static func loadOpenCodeCredentials(env: [String: String] = ProcessInfo.processInfo.environment) throws -> Credentials? {
        for path in LocalPaths.opencodeAuthPaths(env: env) where FileManager.default.fileExists(atPath: path.path) {
            let data = try Data(contentsOf: path)
            guard let root = try? JSONDecoder().decode([String: OpenCodeOAuth].self, from: data),
                  let oauth = root["openai"],
                  oauth.type == "oauth"
            else {
                continue
            }

            let accessToken = oauth.access.trimmingCharacters(in: .whitespacesAndNewlines)
            let refreshToken = oauth.refresh.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !accessToken.isEmpty, !refreshToken.isEmpty else { continue }

            return Credentials(
                accessToken: accessToken,
                refreshToken: refreshToken,
                accountID: oauth.accountId ?? Self.extractAccountID(fromJWT: accessToken),
                lastRefresh: nil,
                expiresAt: oauth.expires.map { Date(timeIntervalSince1970: $0 / 1000.0) }
            )
        }
        return nil
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
        if http.statusCode == 429 {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = body.isEmpty ? "Refresh failed (429)" : "Refresh failed (429): \(body)"
            throw ProviderErrorState.rateLimited(message, retryAfter: http.retryAfterTimeInterval)
        }
        if http.statusCode == 401 {
            let body = String(data: data, encoding: .utf8)?.lowercased() ?? ""
            if body.contains("refresh_token_reused") {
                throw ProviderErrorState.endpointError("Codex auth is stale (refresh token reused). Run 'codex login' and then refresh.")
            }
            throw ProviderErrorState.endpointError("Codex token expired. Run 'codex login' and then refresh.")
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
            accountID: credentials.accountID
                ?? Self.extractAccountID(fromJWT: decoded.idToken)
                ?? Self.extractAccountID(fromJWT: decoded.accessToken ?? credentials.accessToken),
            lastRefresh: Date(),
            expiresAt: decoded.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
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

    private static func extractAccountID(fromJWT token: String?) -> String? {
        guard let token, !token.isEmpty else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        guard let data = Data(base64URLEncoded: String(parts[1])),
              let claims = try? JSONDecoder().decode(JWTClaims.self, from: data)
        else {
            return nil
        }
        return claims.chatgptAccountID ?? claims.openAIAuth?.chatgptAccountID ?? claims.organizations?.first?.id
    }

    private static func shouldTryNextCredential(after error: ProviderErrorState) -> Bool {
        switch error {
        case .authNeeded, .tokenExpired:
            return true
        case .endpointError(let message):
            let lowered = message.lowercased()
            return lowered.contains("refresh token reused")
                || lowered.contains("token expired")
                || lowered.contains("401")
                || lowered.contains("403")
                || lowered.contains("unauthorized")
                || lowered.contains("invalid api key")
                || lowered.contains("invalid_api_key")
        case .rateLimited, .parseError, .networkError:
            return false
        }
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }
}

#if DEBUG
extension CodexClient {
    static func decodeUsageResponse(_ data: Data) throws -> (Double, Double?) {
        let usage = try JSONDecoder().decode(UsageResponse.self, from: data)
        return (usage.rateLimit.primaryWindow?.usedPercent ?? 0, usage.rateLimit.secondaryWindow?.usedPercent)
    }

    static func decodeOpenCodeCredentials(_ data: Data) throws -> (access: String, refresh: String, accountID: String?, expiresAt: Date?)? {
        guard let root = try? JSONDecoder().decode([String: OpenCodeOAuth].self, from: data),
              let oauth = root["openai"],
              oauth.type == "oauth"
        else {
            return nil
        }
        return (
            access: oauth.access,
            refresh: oauth.refresh,
            accountID: oauth.accountId ?? Self.extractAccountID(fromJWT: oauth.access),
            expiresAt: oauth.expires.map { Date(timeIntervalSince1970: $0 / 1000.0) }
        )
    }

    static func extractAccountIDForTests(_ token: String) -> String? {
        Self.extractAccountID(fromJWT: token)
    }

    static func shouldTryNextCredentialForTests(_ error: ProviderErrorState) -> Bool {
        Self.shouldTryNextCredential(after: error)
    }
}
#endif
