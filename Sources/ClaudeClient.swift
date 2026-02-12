import Foundation

struct ClaudeClient: ProviderClient {
    let providerID: ProviderID = .claude

    func fetchUsage(now: Date) async -> ProviderUsageResult {
        do {
            let credentials = try Self.loadCredentials()
            if let expiresAt = credentials.expiresAt, expiresAt <= Date() {
                throw ProviderErrorState.tokenExpired
            }
            let response = try await Self.fetchUsage(accessToken: credentials.accessToken)
            return ProviderUsageResult(
                provider: .claude,
                primaryWindow: response.fiveHour?.asWindow,
                secondaryWindow: response.sevenDay?.asWindow,
                accountLabel: credentials.rateLimitTier,
                lastUpdated: now,
                errorState: nil,
                isStale: false
            )
        } catch let error as ProviderErrorState {
            return ProviderUsageResult(provider: .claude, primaryWindow: nil, secondaryWindow: nil, accountLabel: nil, lastUpdated: now, errorState: error, isStale: false)
        } catch {
            return ProviderUsageResult(provider: .claude, primaryWindow: nil, secondaryWindow: nil, accountLabel: nil, lastUpdated: now, errorState: .networkError(error.localizedDescription), isStale: false)
        }
    }

    private struct Credentials {
        let accessToken: String
        let expiresAt: Date?
        let rateLimitTier: String?
    }

    private struct RootCredentials: Decodable {
        let claudeAiOauth: ClaudeOAuth?
    }

    private struct ClaudeOAuth: Decodable {
        let accessToken: String?
        let expiresAt: Double?
        let rateLimitTier: String?
    }

    private struct OAuthUsageResponse: Decodable {
        let fiveHour: OAuthWindow?
        let sevenDay: OAuthWindow?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    private struct OAuthWindow: Decodable {
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        var asWindow: UsageWindow? {
            guard let utilization else { return nil }
            return UsageWindow(usedPercent: utilization * 100, resetAt: ClaudeClient.parseISO8601(self.resetsAt), windowSeconds: nil)
        }
    }

    private static func loadCredentials() throws -> Credentials {
        let path = LocalPaths.claudeCredentialsPath()
        if FileManager.default.fileExists(atPath: path.path) {
            let data = try Data(contentsOf: path)
            if let root = try? JSONDecoder().decode(RootCredentials.self, from: data),
               let oauth = root.claudeAiOauth,
               let token = oauth.accessToken,
               !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                let expiresAt = oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000.0) }
                return Credentials(accessToken: token, expiresAt: expiresAt, rateLimitTier: oauth.rateLimitTier)
            }
        }

        if let setupToken = Self.loadSetupTokenFromCLI() {
            return Credentials(accessToken: setupToken, expiresAt: nil, rateLimitTier: "Setup token")
        }

        throw ProviderErrorState.authNeeded
    }

    private static func loadSetupTokenFromCLI() -> String? {
        let output: String
        do {
            output = try CommandRunner.run("/usr/bin/env", arguments: ["claude", "setup-token"], timeout: 8)
        } catch {
            return nil
        }
        return self.parseSetupToken(output)
    }

    private static func parseSetupToken(_ output: String) -> String? {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let tokenLine = lines.first(where: { $0.lowercased().contains("setup-token") || $0.lowercased().contains("token") }) {
            let parts = tokenLine.components(separatedBy: CharacterSet.whitespaces)
            if let token = parts.last, token.count >= 20 {
                return token
            }
        }

        if let fallback = lines.last, fallback.count >= 20 {
            return fallback
        }
        return nil
    }

    private static func fetchUsage(accessToken: String) async throws -> OAuthUsageResponse {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw ProviderErrorState.endpointError("Invalid Claude endpoint")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("AIUsageMonitor", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderErrorState.endpointError("Invalid Claude response")
        }
        switch http.statusCode {
        case 200:
            guard let decoded = try? JSONDecoder().decode(OAuthUsageResponse.self, from: data) else {
                throw ProviderErrorState.parseError("Invalid Claude usage payload")
            }
            return decoded
        case 401, 403:
            throw ProviderErrorState.tokenExpired
        default:
            throw ProviderErrorState.endpointError("HTTP \(http.statusCode)")
        }
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
extension ClaudeClient {
    static func decodeUsageResponse(_ data: Data) throws -> (Double?, Double?) {
        let decoded = try JSONDecoder().decode(OAuthUsageResponse.self, from: data)
        return (decoded.fiveHour?.utilization, decoded.sevenDay?.utilization)
    }

    static func parseSetupTokenOutput(_ output: String) -> String? {
        self.parseSetupToken(output)
    }
}
#endif
