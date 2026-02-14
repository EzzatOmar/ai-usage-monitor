import Foundation

struct MinimaxClient: ProviderClient {
    let providerID: ProviderID = .minimax

    func fetchUsage(now: Date) async -> ProviderUsageResult {
        guard let apiKey = Self.loadAPIKey() else {
            return ProviderUsageResult(
                provider: .minimax,
                primaryWindow: nil,
                secondaryWindow: nil,
                accountLabel: nil,
                lastUpdated: now,
                errorState: .authNeeded,
                isStale: false
            )
        }

        do {
            let usage = try await Self.fetchUsage(apiKey: apiKey, now: now)
            return ProviderUsageResult(
                provider: .minimax,
                primaryWindow: usage.primary,
                secondaryWindow: usage.secondary,
                accountLabel: usage.accountLabel,
                lastUpdated: now,
                errorState: nil,
                isStale: false
            )
        } catch let error as ProviderErrorState {
            return ProviderUsageResult(
                provider: .minimax,
                primaryWindow: nil,
                secondaryWindow: nil,
                accountLabel: nil,
                lastUpdated: now,
                errorState: error,
                isStale: false
            )
        } catch {
            return ProviderUsageResult(
                provider: .minimax,
                primaryWindow: nil,
                secondaryWindow: nil,
                accountLabel: nil,
                lastUpdated: now,
                errorState: .networkError(error.localizedDescription),
                isStale: false
            )
        }
    }

    private struct CodingPlanResponse: Decodable {
        let modelRemains: [ModelRemain]?
        let baseResp: BaseResp?

        enum CodingKeys: String, CodingKey {
            case modelRemains = "model_remains"
            case baseResp = "base_resp"
        }
    }

    private struct ModelRemain: Decodable {
        let startTime: Int64?
        let endTime: Int64?
        let remainsTime: Int64?
        let currentIntervalTotalCount: Int?
        let currentIntervalUsageCount: Int?
        let modelName: String?

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case endTime = "end_time"
            case remainsTime = "remains_time"
            case currentIntervalTotalCount = "current_interval_total_count"
            case currentIntervalUsageCount = "current_interval_usage_count"
            case modelName = "model_name"
        }
    }

    private struct BaseResp: Decodable {
        let statusCode: Int?
        let statusMsg: String?

        enum CodingKeys: String, CodingKey {
            case statusCode = "status_code"
            case statusMsg = "status_msg"
        }
    }

    private struct UsageResult {
        let primary: UsageWindow?
        let secondary: UsageWindow?
        let accountLabel: String?
    }

    private static func loadAPIKey() -> String? {
        if let stored = AuthStore.loadMinimaxAPIKey(), !stored.isEmpty {
            return stored
        }
        let env = ProcessInfo.processInfo.environment
        if let key = env["MINIMAX_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        return nil
    }

    private static func fetchUsage(apiKey: String, now: Date) async throws -> UsageResult {
        var request = URLRequest(url: URL(string: "https://api.minimax.io/v1/api/openplatform/coding_plan/remains")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
        request.setValue("https://platform.minimax.com/user-center/payment/coding-plan", forHTTPHeaderField: "referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderErrorState.endpointError("Invalid Minimax response")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ProviderErrorState.tokenExpired
            }
            throw ProviderErrorState.endpointError("HTTP \(http.statusCode)")
        }

        guard let codingPlan = try? JSONDecoder().decode(CodingPlanResponse.self, from: data),
              let baseResp = codingPlan.baseResp,
              baseResp.statusCode == 0,
              let modelRemains = codingPlan.modelRemains,
              let first = modelRemains.first
        else {
            throw ProviderErrorState.parseError("Invalid Minimax coding plan payload")
        }

        let remaining = first.currentIntervalUsageCount ?? 0
        let total = first.currentIntervalTotalCount ?? 0

        let usedPercent: Double
        if total > 0 {
            let used = total - remaining
            usedPercent = (Double(used) / Double(total)) * 100
        } else {
            usedPercent = 0
        }

        let resetAt: Date?
        if let endTime = first.endTime {
            resetAt = Date(timeIntervalSince1970: Double(endTime) / 1000.0)
        } else {
            resetAt = nil
        }

        let fiveHourWindow = UsageWindow(
            usedPercent: max(0, min(100, usedPercent)),
            resetAt: resetAt,
            windowSeconds: 18000
        )

        var accountLabel = "\(total - remaining)/\(total) prompts"
        if let modelName = first.modelName {
            accountLabel = "\(modelName): \(accountLabel)"
        }

        return UsageResult(primary: fiveHourWindow, secondary: nil, accountLabel: accountLabel)
    }

#if DEBUG
    static func decodeUsageResponse(_ data: Data) throws -> (primary: UsageWindow?, accountLabel: String?) {
        guard let codingPlan = try? JSONDecoder().decode(CodingPlanResponse.self, from: data),
              let modelRemains = codingPlan.modelRemains,
              let first = modelRemains.first
        else {
            throw ProviderErrorState.parseError("Invalid Minimax coding plan payload")
        }

        let remaining = first.currentIntervalUsageCount ?? 0
        let total = first.currentIntervalTotalCount ?? 0

        let usedPercent: Double
        if total > 0 {
            let used = total - remaining
            usedPercent = (Double(used) / Double(total)) * 100
        } else {
            usedPercent = 0
        }

        let resetAt: Date?
        if let endTime = first.endTime {
            resetAt = Date(timeIntervalSince1970: Double(endTime) / 1000.0)
        } else {
            resetAt = nil
        }

        let fiveHourWindow = UsageWindow(
            usedPercent: max(0, min(100, usedPercent)),
            resetAt: resetAt,
            windowSeconds: 18000
        )

        var accountLabel = "\(total - remaining)/\(total) prompts"
        if let modelName = first.modelName {
            accountLabel = "\(modelName): \(accountLabel)"
        }

        return (primary: fiveHourWindow, accountLabel: accountLabel)
    }
#endif
}
