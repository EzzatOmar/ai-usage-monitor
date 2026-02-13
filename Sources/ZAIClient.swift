import Foundation

struct ZAIClient: ProviderClient {
    let providerID: ProviderID = .zai

    func fetchUsage(now: Date) async -> ProviderUsageResult {
        guard let apiKey = Self.loadAPIKey() else {
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

        do {
            let usage = try await Self.fetchQuota(apiKey: apiKey)
            return ProviderUsageResult(
                provider: .zai,
                primaryWindow: usage.primary,
                secondaryWindow: usage.secondary,
                accountLabel: usage.accountLabel,
                lastUpdated: now,
                errorState: nil,
                isStale: false
            )
        } catch let error as ProviderErrorState {
            return ProviderUsageResult(
                provider: .zai,
                primaryWindow: nil,
                secondaryWindow: nil,
                accountLabel: nil,
                lastUpdated: now,
                errorState: error,
                isStale: false
            )
        } catch {
            return ProviderUsageResult(
                provider: .zai,
                primaryWindow: nil,
                secondaryWindow: nil,
                accountLabel: nil,
                lastUpdated: now,
                errorState: .networkError(error.localizedDescription),
                isStale: false
            )
        }
    }

    private struct ZAIEnvelope<T: Decodable>: Decodable {
        let success: Bool
        let data: T?
    }

    private struct QuotaLimitData: Decodable {
        let limits: [QuotaLimit]
    }

    private struct QuotaLimit: Decodable {
        let type: String
        let usage: Double?
        let currentValue: Double?
        let percentage: Double?
        let nextResetTime: Double?
    }

    private struct ModelUsageData: Decodable {
        let totalUsage: WeeklyUsage?
    }

    private struct WeeklyUsage: Decodable {
        let totalModelCallCount: Int?
        let totalTokensUsage: Double?
    }

    private struct QuotaResult {
        let primary: UsageWindow?
        let secondary: UsageWindow?
        let accountLabel: String?
    }

    private static func loadAPIKey() -> String? {
        if let stored = AuthStore.loadZAIAPIKey(), !stored.isEmpty {
            return stored
        }
        let env = ProcessInfo.processInfo.environment
        for keyName in ["ZAI_API_KEY", "ZAI_KEY", "ZHIPU_API_KEY", "ZHIPUAI_API_KEY"] {
            if let key = env[keyName]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                return key
            }
        }
        return nil
    }

    private static func fetchQuota(apiKey: String) async throws -> QuotaResult {
        var request = URLRequest(url: URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderErrorState.endpointError("Invalid Z.AI response")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ProviderErrorState.tokenExpired
            }
            throw ProviderErrorState.endpointError("HTTP \(http.statusCode)")
        }

        guard let envelope = try? JSONDecoder().decode(ZAIEnvelope<QuotaLimitData>.self, from: data),
              envelope.success,
              let quotaData = envelope.data
        else {
            throw ProviderErrorState.parseError("Invalid Z.AI quota payload")
        }

        var tokenWindow: UsageWindow?
        var requestWindow: UsageWindow?
        for item in quotaData.limits {
            let usedPercent: Double
            if let pct = item.percentage {
                usedPercent = pct
            } else if let used = item.currentValue, let total = item.usage, total > 0 {
                usedPercent = (used / total) * 100
            } else {
                continue
            }
            let resetAt = item.nextResetTime.map { Date(timeIntervalSince1970: $0 / 1000.0) }
            let window = UsageWindow(usedPercent: max(0, min(100, usedPercent)), resetAt: resetAt, windowSeconds: nil)
            if item.type == "TOKENS_LIMIT" {
                tokenWindow = window
            } else if item.type == "TIME_LIMIT" {
                requestWindow = window
            }
        }

        let weeklyLabel = try await Self.fetchWeeklyUsageLabel(apiKey: apiKey)
        return QuotaResult(primary: tokenWindow ?? requestWindow, secondary: requestWindow, accountLabel: weeklyLabel)
    }

    private static func fetchWeeklyUsageLabel(apiKey: String) async throws -> String? {
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        guard let start = calendar.date(byAdding: .day, value: -7, to: now) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        let startTime = formatter.string(from: start) + "+00:00:00"
        let endTime = formatter.string(from: now) + "+23:59:59"
        guard let url = URL(string: "https://api.z.ai/api/monitor/usage/model-usage?startTime=\(startTime)&endTime=\(endTime)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }

        guard let envelope = try? JSONDecoder().decode(ZAIEnvelope<ModelUsageData>.self, from: data),
              envelope.success,
              let total = envelope.data?.totalUsage
        else {
            return nil
        }

        let calls = total.totalModelCallCount ?? 0
        let tokens = Int((total.totalTokensUsage ?? 0).rounded())
        return "7d: \(calls) calls, \(tokens) tokens"
    }
}
