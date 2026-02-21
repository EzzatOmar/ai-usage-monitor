import Foundation

struct KimiClient: ProviderClient {
    let providerID: ProviderID = .kimi

    func fetchUsage(now: Date) async -> ProviderUsageResult {
        guard let apiKey = Self.loadAPIKey() else {
            return ProviderUsageResult(
                provider: .kimi,
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
                provider: .kimi,
                primaryWindow: usage.primary,
                secondaryWindow: usage.secondary,
                accountLabel: usage.accountLabel,
                lastUpdated: now,
                errorState: nil,
                isStale: false
            )
        } catch let error as ProviderErrorState {
            return ProviderUsageResult(
                provider: .kimi,
                primaryWindow: nil,
                secondaryWindow: nil,
                accountLabel: nil,
                lastUpdated: now,
                errorState: error,
                isStale: false
            )
        } catch {
            return ProviderUsageResult(
                provider: .kimi,
                primaryWindow: nil,
                secondaryWindow: nil,
                accountLabel: nil,
                lastUpdated: now,
                errorState: .networkError(error.localizedDescription),
                isStale: false
            )
        }
    }

    private struct UsageResponse: Decodable {
        let usage: LimitDetail?
        let limits: [LimitItem]?
    }

    private struct LimitItem: Decodable {
        let name: String?
        let title: String?
        let scope: String?
        let duration: FlexibleInt?
        let timeUnit: String?
        let window: WindowSpec?
        let detail: LimitDetail?
    }

    private struct WindowSpec: Decodable {
        let duration: FlexibleInt?
        let timeUnit: String?
    }

    private struct LimitDetail: Decodable {
        let name: String?
        let title: String?
        let used: FlexibleInt?
        let remaining: FlexibleInt?
        let limit: FlexibleInt?
        let resetAt: String?
        let resetIn: FlexibleInt?
        let resetTime: String?
        let resetSeconds: FlexibleInt?

        enum CodingKeys: String, CodingKey {
            case name
            case title
            case used
            case remaining
            case limit
            case resetAt
            case resetIn
            case resetTime
            case resetSeconds = "reset_in"
        }
    }

    private struct FlexibleInt: Decodable {
        let value: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                self.value = intValue
                return
            }
            if let stringValue = try? container.decode(String.self) {
                self.value = Int(stringValue)
                return
            }
            self.value = nil
        }
    }

    private struct ParsedWindow {
        let label: String
        let window: UsageWindow
    }

    private struct UsageResult {
        let primary: UsageWindow?
        let secondary: UsageWindow?
        let accountLabel: String?
    }

    private static func loadAPIKey() -> String? {
        if let stored = AuthStore.loadKimiAPIKey(), !stored.isEmpty {
            return stored
        }

        let env = ProcessInfo.processInfo.environment
        for keyName in ["KIMI_API_KEY", "KIMI_CODE_API_KEY", "KIMI_KEY"] {
            if let value = env[keyName]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }

        if let baseURL = env["ANTHROPIC_BASE_URL"]?.lowercased(),
           baseURL.contains("api.kimi.com/coding"),
           let value = env["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }

        return nil
    }

    private static func fetchUsage(apiKey: String, now: Date) async throws -> UsageResult {
        var request = URLRequest(url: URL(string: "https://api.kimi.com/coding/v1/usages")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderErrorState.endpointError("Invalid Kimi response")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ProviderErrorState.tokenExpired
            }
            throw ProviderErrorState.endpointError("HTTP \(http.statusCode)")
        }

        let decoded: UsageResponse
        do {
            decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw ProviderErrorState.parseError("Invalid Kimi usage payload")
        }

        return parseUsageResponse(decoded, now: now)
    }

    private static func parseUsageResponse(_ response: UsageResponse, now: Date) -> UsageResult {
        var parsedWindows: [ParsedWindow] = []

        for item in response.limits ?? [] {
            let duration = item.window?.duration?.value ?? item.duration?.value
            let timeUnit = item.window?.timeUnit ?? item.timeUnit
            let seconds = duration.flatMap { durationToSeconds($0, timeUnit: timeUnit) }
            let label = item.detail?.name ?? item.detail?.title ?? item.name ?? item.title ?? item.scope ?? "Limit"

            if let detail = item.detail,
               let window = usageWindow(from: detail, windowSeconds: seconds, now: now) {
                parsedWindows.append(ParsedWindow(label: label, window: window))
            }
        }

        let weekly = parsedWindows.first { isWeekly(label: $0.label, windowSeconds: $0.window.windowSeconds) }

        let usageWeekly = usageSummaryWindow(from: response.usage, now: now)

        let shorterThanWeekly = parsedWindows
            .filter { !isWeekly(label: $0.label, windowSeconds: $0.window.windowSeconds) }
            .sorted { ($0.window.windowSeconds ?? Int.max) < ($1.window.windowSeconds ?? Int.max) }

        let primary = shorterThanWeekly.first?.window ?? weekly?.window ?? usageWeekly
        let secondary: UsageWindow?
        if let weeklyWindow = weekly?.window, weeklyWindow != primary {
            secondary = weeklyWindow
        } else if let usageWeekly, usageWeekly != primary {
            secondary = usageWeekly
        } else {
            secondary = nil
        }

        var accountLabel: String? = "Model: kimi-for-coding (powered by kimi-k2.5)"
        if let usage = response.usage {
            let usedValue = usage.used?.value
            let limitValue = usage.limit?.value
            let remainingValue = usage.remaining?.value
            let used = usedValue ?? ((limitValue ?? 0) - (remainingValue ?? 0))
            if let limit = limitValue, limit > 0 {
                accountLabel = "Kimi Code: \(max(used, 0))/\(limit) requests"
            }
        }

        return UsageResult(primary: primary, secondary: secondary, accountLabel: accountLabel)
    }

    private static func usageSummaryWindow(from detail: LimitDetail?, now: Date) -> UsageWindow? {
        guard let detail,
              let limit = detail.limit?.value,
              limit > 0
        else { return nil }

        let used: Int
        if let explicitUsed = detail.used?.value {
            used = explicitUsed
        } else if let remaining = detail.remaining?.value {
            used = limit - remaining
        } else {
            return nil
        }

        let usedPercent = (Double(used) / Double(limit)) * 100
        return UsageWindow(
            usedPercent: max(0, min(100, usedPercent)),
            resetAt: parseResetAt(detail: detail, now: now),
            windowSeconds: 7 * 24 * 3600
        )
    }

    private static func usageWindow(from detail: LimitDetail, windowSeconds: Int?, now: Date) -> UsageWindow? {
        guard let limit = detail.limit?.value, limit > 0 else { return nil }

        let used: Int
        if let explicitUsed = detail.used?.value {
            used = explicitUsed
        } else if let remaining = detail.remaining?.value {
            used = limit - remaining
        } else {
            return nil
        }

        let usedPercent = (Double(used) / Double(limit)) * 100

        let resetAt = parseResetAt(detail: detail, now: now)
        return UsageWindow(
            usedPercent: max(0, min(100, usedPercent)),
            resetAt: resetAt,
            windowSeconds: windowSeconds
        )
    }

    private static func parseResetAt(detail: LimitDetail, now: Date) -> Date? {
        if let value = detail.resetAt ?? detail.resetTime,
           let parsed = parseISO8601(value) {
            return parsed
        }

        if let seconds = detail.resetIn?.value ?? detail.resetSeconds?.value,
           seconds > 0 {
            return now.addingTimeInterval(Double(seconds))
        }

        return nil
    }

    private static func parseISO8601(_ value: String) -> Date? {
        if let date = Self.fractionalISO8601.date(from: value) {
            return date
        }

        if let date = Self.basicISO8601.date(from: value) {
            return date
        }

        if value.contains("."), value.hasSuffix("Z") {
            let components = value.dropLast().split(separator: ".", maxSplits: 1)
            if components.count == 2 {
                let trimmedFraction = components[1].prefix(6)
                let rewritten = "\(components[0]).\(trimmedFraction)Z"
                if let date = Self.fractionalISO8601.date(from: rewritten) {
                    return date
                }
            }
        }

        return nil
    }

    private static func durationToSeconds(_ duration: Int, timeUnit: String?) -> Int? {
        guard duration > 0 else { return nil }
        let unit = (timeUnit ?? "").uppercased()

        if unit.contains("MINUTE") {
            return duration * 60
        }
        if unit.contains("HOUR") {
            return duration * 3600
        }
        if unit.contains("DAY") {
            return duration * 86400
        }
        if unit.contains("WEEK") {
            return duration * 604800
        }

        return duration
    }

    private static func isWeekly(label: String, windowSeconds: Int?) -> Bool {
        if let seconds = windowSeconds, seconds >= 6 * 24 * 3600 {
            return true
        }

        let lowered = label.lowercased()
        return lowered.contains("week") || lowered.contains("7d")
    }

    private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let basicISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

#if DEBUG
    static func decodeUsageResponse(_ data: Data, now: Date) throws -> (primary: UsageWindow?, secondary: UsageWindow?, accountLabel: String?) {
        let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
        let usage = parseUsageResponse(decoded, now: now)
        return (primary: usage.primary, secondary: usage.secondary, accountLabel: usage.accountLabel)
    }
#endif
}
