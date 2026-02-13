import Foundation

struct ClaudeClient: ProviderClient {
    let providerID: ProviderID = .claude

    func fetchUsage(now: Date) async -> ProviderUsageResult {
        do {
            let candidates = try Self.loadCredentialCandidates()
            guard !candidates.isEmpty else {
                throw ProviderErrorState.authNeeded
            }

            var keychainExpired = false
            var lastProviderError: ProviderErrorState?

            for candidate in candidates {
                if let expiresAt = candidate.expiresAt, expiresAt <= Date() {
                    if candidate.source == .keychain {
                        keychainExpired = true
                    }
                    lastProviderError = .endpointError("Token expired - run 'claude' in terminal to refresh")
                    continue
                }

                do {
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
                } catch let error as ProviderErrorState {
                    lastProviderError = error
                    continue
                }
            }

            if keychainExpired {
                throw ProviderErrorState.endpointError("Run 'claude' in terminal to refresh token")
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

    private enum CredentialSource {
        case pastedSetupToken
        case keychain
        case credentialFile
        case environment
    }

    private struct Credentials {
        let accessToken: String
        let expiresAt: Date?
        let rateLimitTier: String?
        let source: CredentialSource
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

    private static func loadCredentialCandidates() throws -> [Credentials] {
        var candidates: [Credentials] = []

        if let keychainCreds = AuthStore.readClaudeKeychainCredentials() {
            candidates.append(Credentials(
                accessToken: keychainCreds.accessToken,
                expiresAt: keychainCreds.expiresAt,
                rateLimitTier: keychainCreds.rateLimitTier,
                source: .keychain
            ))
        }

        if let pastedToken = AuthStore.loadClaudeSetupToken() {
            candidates.append(Credentials(accessToken: pastedToken, expiresAt: nil, rateLimitTier: "Setup token", source: .pastedSetupToken))
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
                    candidates.append(Credentials(accessToken: token, expiresAt: expiresAt, rateLimitTier: oauth.rateLimitTier, source: .credentialFile))
                }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let directToken = json["accessToken"] as? String,
                   !directToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    candidates.append(Credentials(accessToken: directToken, expiresAt: nil, rateLimitTier: "Claude CLI", source: .credentialFile))
                }
            }
        }

        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_ACCESS_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !envToken.isEmpty
        {
            candidates.append(Credentials(accessToken: envToken, expiresAt: nil, rateLimitTier: "Environment", source: .environment))
        }

        return candidates
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
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(180) ?? ""
            if body.isEmpty {
                throw ProviderErrorState.endpointError("HTTP \(http.statusCode)")
            }
            throw ProviderErrorState.endpointError("HTTP \(http.statusCode): \(body)")
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
}
#endif
