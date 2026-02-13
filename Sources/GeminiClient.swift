import Foundation

struct GeminiClient: ProviderClient {
    let providerID: ProviderID = .gemini

    func fetchUsage(now: Date) async -> ProviderUsageResult {
        do {
            let authType = try Self.loadAuthType()
            if authType == "api-key" || authType == "vertex-ai" {
                throw ProviderErrorState.authNeeded
            }
            let credentials = try Self.loadCredentials()
            if let expiry = credentials.expiryDate, expiry <= Date() {
                throw ProviderErrorState.tokenExpired
            }
            let codeAssist = try await Self.loadCodeAssist(accessToken: credentials.accessToken)
            let quota = try await Self.retrieveQuota(accessToken: credentials.accessToken, projectID: codeAssist.projectID)
            return ProviderUsageResult(
                provider: .gemini,
                primaryWindow: quota.primary,
                secondaryWindow: quota.secondary,
                modelWindows: quota.modelWindows,
                accountLabel: codeAssist.tierLabel,
                lastUpdated: now,
                errorState: nil,
                isStale: false
            )
        } catch let error as ProviderErrorState {
            return ProviderUsageResult(provider: .gemini, primaryWindow: nil, secondaryWindow: nil, accountLabel: nil, lastUpdated: now, errorState: error, isStale: false)
        } catch {
            return ProviderUsageResult(provider: .gemini, primaryWindow: nil, secondaryWindow: nil, accountLabel: nil, lastUpdated: now, errorState: .networkError(error.localizedDescription), isStale: false)
        }
    }

    private struct Credentials {
        let accessToken: String
        let expiryDate: Date?
    }

    private struct LoadCodeAssistResponse: Decodable {
        let currentTier: CurrentTier?
        let cloudaicompanionProject: String?

        struct CurrentTier: Decodable {
            let id: String?
        }
    }

    private struct QuotaResponse: Decodable {
        let buckets: [QuotaBucket]
    }

    private struct QuotaBucket: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
        let modelId: String?
    }

    private struct QuotaMapping {
        let primary: UsageWindow?
        let secondary: UsageWindow?
        let modelWindows: [ModelUsageWindow]
    }

    private struct CodeAssistContext {
        let projectID: String?
        let tierLabel: String?
    }

    private static func loadAuthType() throws -> String {
        let path = LocalPaths.geminiSettingsPath()
        guard FileManager.default.fileExists(atPath: path.path) else { return "oauth-personal" }
        let json = try JSONFile.readDictionary(at: path)
        return (((json["security"] as? [String: Any])?["auth"] as? [String: Any])?["selectedType"] as? String) ?? "oauth-personal"
    }

    private static func loadCredentials() throws -> Credentials {
        let path = LocalPaths.geminiOAuthPath()
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ProviderErrorState.authNeeded
        }
        let json = try JSONFile.readDictionary(at: path)
        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw ProviderErrorState.authNeeded
        }
        let expiryDate: Date?
        if let expiryMillis = json["expiry_date"] as? Double {
            expiryDate = Date(timeIntervalSince1970: expiryMillis / 1000.0)
        } else {
            expiryDate = nil
        }
        return Credentials(accessToken: accessToken, expiryDate: expiryDate)
    }

    private static func loadCodeAssist(accessToken: String) async throws -> CodeAssistContext {
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist") else {
            throw ProviderErrorState.endpointError("Invalid Gemini endpoint")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{\"metadata\":{\"ideType\":\"GEMINI_CLI\",\"pluginType\":\"GEMINI\"}}".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderErrorState.endpointError("Invalid Gemini loadCodeAssist response")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw ProviderErrorState.tokenExpired }
            throw ProviderErrorState.endpointError("HTTP \(http.statusCode)")
        }
        guard let parsed = try? JSONDecoder().decode(LoadCodeAssistResponse.self, from: data) else {
            throw ProviderErrorState.parseError("Invalid loadCodeAssist payload")
        }
        let tier = parsed.currentTier?.id
        let tierLabel: String?
        switch tier {
        case "standard-tier": tierLabel = "Paid"
        case "free-tier": tierLabel = "Free"
        case "legacy-tier": tierLabel = "Legacy"
        default: tierLabel = nil
        }
        return CodeAssistContext(projectID: parsed.cloudaicompanionProject, tierLabel: tierLabel)
    }

    private static func retrieveQuota(accessToken: String, projectID: String?) async throws -> QuotaMapping {
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota") else {
            throw ProviderErrorState.endpointError("Invalid Gemini quota endpoint")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let projectID, !projectID.isEmpty {
            request.httpBody = Data("{\"project\":\"\(projectID)\"}".utf8)
        } else {
            request.httpBody = Data("{}".utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderErrorState.endpointError("Invalid Gemini quota response")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw ProviderErrorState.tokenExpired }
            throw ProviderErrorState.endpointError("HTTP \(http.statusCode)")
        }
        guard let decoded = try? JSONDecoder().decode(QuotaResponse.self, from: data) else {
            throw ProviderErrorState.parseError("Invalid quota payload")
        }
        return Self.mapBuckets(decoded.buckets)
    }

    private static func mapBuckets(_ buckets: [QuotaBucket]) -> QuotaMapping {
        var proCandidates: [UsageWindow] = []
        var flashCandidates: [UsageWindow] = []
        var fallbackCandidates: [UsageWindow] = []
        var modelWindows: [ModelUsageWindow] = []

        for bucket in buckets {
            guard let fraction = bucket.remainingFraction else { continue }
            let used = (1 - fraction) * 100
            let window = UsageWindow(
                usedPercent: max(0, min(100, used)),
                resetAt: Self.parseISO8601(bucket.resetTime),
                windowSeconds: 24 * 60 * 60
            )
            
            if let modelId = bucket.modelId {
                modelWindows.append(ModelUsageWindow(modelId: modelId, window: window))
            }
            
            fallbackCandidates.append(window)
            let model = (bucket.modelId ?? "").lowercased()
            if model.contains("pro") {
                proCandidates.append(window)
            }
            if model.contains("flash") {
                flashCandidates.append(window)
            }
        }

        let primary = proCandidates.sorted(by: { $0.remainingPercent < $1.remainingPercent }).first
            ?? fallbackCandidates.sorted(by: { $0.remainingPercent < $1.remainingPercent }).first
        let secondary = flashCandidates.sorted(by: { $0.remainingPercent < $1.remainingPercent }).first
        
        let filteredModels = modelWindows.filter { $0.modelId.lowercased().hasPrefix("gemini-3") }
        let sortedModels = filteredModels.sorted(by: { $0.modelId < $1.modelId })
        
        return QuotaMapping(primary: primary, secondary: secondary, modelWindows: sortedModels)
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
extension GeminiClient {
    static func decodeQuota(_ data: Data) throws -> (Double?, Double?, [ModelUsageWindow]) {
        let decoded = try JSONDecoder().decode(QuotaResponse.self, from: data)
        let mapped = mapBuckets(decoded.buckets)
        return (mapped.primary?.usedPercent, mapped.secondary?.usedPercent, mapped.modelWindows)
    }
}
#endif
