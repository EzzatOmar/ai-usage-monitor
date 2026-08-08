import Foundation

struct ClaudeClient: ProviderClient {
    let providerID: ProviderID = .claude

    static let anthropicUserAgent = "claude-cli/2.1.80"
    private static let maxRateLimitAttempts = 2

    func fetchUsage(now: Date, mode: UsageRefreshMode) async -> ProviderUsageResult {
        do {
            var lastProviderError: ProviderErrorState?

            let allowKeychainInteraction = mode.allowsCredentialInteraction(for: .claude)
            if let keychainCredentials = await ClaudeCredentialSession.shared.credentials(
                allowInteraction: allowKeychainInteraction
            ) {
                let candidate = Credentials(
                    accessToken: keychainCredentials.accessToken,
                    expiresAt: keychainCredentials.expiresAt,
                    rateLimitTier: keychainCredentials.rateLimitTier
                )

                if let expiresAt = candidate.expiresAt, expiresAt <= Date() {
                    await ClaudeCredentialSession.shared.clear()
                    lastProviderError = .tokenExpired
                } else {
                    do {
                        return try await Self.fetchUsageResult(candidate: candidate, now: now)
                    } catch let error as ProviderErrorState {
                        if error == .tokenExpired {
                            await ClaudeCredentialSession.shared.clear()
                        }
                        lastProviderError = error
                    }
                }
            }

            for candidate in try Self.loadNonKeychainCredentialCandidates() {
                if let expiresAt = candidate.expiresAt, expiresAt <= Date() {
                    lastProviderError = .tokenExpired
                    continue
                }

                do {
                    return try await Self.fetchUsageResult(candidate: candidate, now: now)
                } catch let error as ProviderErrorState {
                    lastProviderError = error
                }
            }

            throw lastProviderError ?? ProviderErrorState.authNeeded
        } catch let error as ProviderErrorState {
            return ProviderUsageResult(
                provider: .claude,
                primaryWindow: nil,
                secondaryWindow: nil,
                accountLabel: nil,
                lastUpdated: now,
                errorState: error,
                isStale: false
            )
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
            return UsageWindow(usedPercent: utilization, resetAt: ClaudeClient.parseISO8601(self.resetsAt), windowSeconds: nil)
        }
    }

    private static func loadNonKeychainCredentialCandidates() throws -> [Credentials] {
        var candidates: [Credentials] = []

        let environment = ProcessInfo.processInfo.environment
        for variableName in ["CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_ACCESS_TOKEN"] {
            if let token = environment[variableName]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !token.isEmpty
            {
                candidates.append(Credentials(
                    accessToken: token,
                    expiresAt: nil,
                    rateLimitTier: variableName == "CLAUDE_CODE_OAUTH_TOKEN" ? "Setup token" : "Environment"
                ))
            }
        }

        for path in self.claudeCredentialPaths() {
            if FileManager.default.fileExists(atPath: path.path) {
                let data = try Data(contentsOf: path)
                if let root = try? JSONDecoder().decode(RootCredentials.self, from: data),
                   let oauth = root.claudeAiOauth,
                   let token = oauth.accessToken,
                   !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    let expiresAt = oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000.0) }
                    candidates.append(Credentials(accessToken: token, expiresAt: expiresAt, rateLimitTier: oauth.rateLimitTier))
                }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let directToken = json["accessToken"] as? String,
                   !directToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    candidates.append(Credentials(accessToken: directToken, expiresAt: nil, rateLimitTier: "Claude CLI"))
                }
            }
        }

        return candidates
    }

    private static func fetchUsageResult(candidate: Credentials, now: Date) async throws -> ProviderUsageResult {
        let response = try await Self.fetchUsage(accessToken: candidate.accessToken)
        return ProviderUsageResult(
            provider: .claude,
            primaryWindow: response.fiveHour?.asWindow,
            secondaryWindow: response.sevenDay?.asWindow,
            accountLabel: candidate.rateLimitTier,
            lastUpdated: now,
            errorState: nil,
            isStale: false
        )
    }

    private static func claudeCredentialPaths() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude").appendingPathComponent(".credentials.json"),
            home.appendingPathComponent(".claude").appendingPathComponent("credentials.json"),
            home.appendingPathComponent(".config").appendingPathComponent("claude").appendingPathComponent("credentials.json"),
        ]
    }

    private static func fetchUsage(accessToken: String) async throws -> OAuthUsageResponse {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            throw ProviderErrorState.endpointError("Invalid Claude endpoint")
        }
        var lastRateLimited: ProviderErrorState?

        for attempt in 0..<Self.maxRateLimitAttempts {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue(Self.anthropicUserAgent, forHTTPHeaderField: "User-Agent")

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
            case 429:
                let body = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let message = body.isEmpty ? "HTTP 429" : "HTTP 429: \(body)"
                let error = ProviderErrorState.rateLimited(message, retryAfter: http.retryAfterTimeInterval)
                lastRateLimited = error
                guard attempt + 1 < Self.maxRateLimitAttempts,
                      let retryAfter = error.retryAfter,
                      retryAfter > 0
                else {
                    throw error
                }
                try? await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
            case 401, 403:
                throw ProviderErrorState.tokenExpired
            default:
                let body = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(180) ?? ""
                if body.isEmpty {
                    throw ProviderErrorState.endpointError("HTTP \(http.statusCode)")
                }
                throw ProviderErrorState.endpointError("HTTP \(http.statusCode): \(body)")
            }
        }

        throw lastRateLimited ?? ProviderErrorState.endpointError("Claude usage request failed")
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

}
#endif
