import Foundation

protocol QwenCloudUsageTransport: Sendable {
    @MainActor
    func fetchUsagePayload() async throws -> Data
}

struct QwenCloudClient: ProviderClient {
    let providerID: ProviderID = .qwenCloud
    private let transport: any QwenCloudUsageTransport

    @MainActor
    init() {
        self.transport = QwenCloudAPIKeyTransport.shared
    }

    init(transport: any QwenCloudUsageTransport) {
        self.transport = transport
    }

    func fetchUsage(now: Date, mode _: UsageRefreshMode) async -> ProviderUsageResult {
        do {
            let data = try await self.transport.fetchUsagePayload()
            let usage = try Self.parseUsageResponse(data)
            return ProviderUsageResult(
                provider: .qwenCloud,
                primaryWindow: usage.primary,
                secondaryWindow: usage.secondary,
                accountLabel: "Individual Token Plan",
                lastUpdated: now,
                errorState: nil,
                isStale: false
            )
        } catch let error as ProviderErrorState {
            return ProviderUsageResult(
                provider: .qwenCloud,
                lastUpdated: now,
                errorState: error
            )
        } catch {
            return ProviderUsageResult(
                provider: .qwenCloud,
                lastUpdated: now,
                errorState: .networkError(error.localizedDescription)
            )
        }
    }

    private struct ParsedUsage {
        let primary: UsageWindow?
        let secondary: UsageWindow?
    }

    private static func parseUsageResponse(_ data: Data) throws -> ParsedUsage {
        let rawObject: Any
        do {
            rawObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProviderErrorState.parseError("Invalid QwenCloud usage payload")
        }

        guard let root = rawObject as? [String: Any] else {
            throw ProviderErrorState.parseError("Invalid QwenCloud usage payload")
        }

        if (root["successResponse"] as? Bool) == false {
            throw self.errorState(
                code: self.stringValue(root["code"]),
                message: self.stringValue(root["message"])
            )
        }

        guard let payload = self.usagePayload(from: root) else {
            throw ProviderErrorState.endpointError("No active QwenCloud Individual Token Plan")
        }

        let primary = self.usageWindow(
            fraction: self.doubleValue(payload["per5HourPercentage"]),
            resetValue: payload["per5HourResetTime"],
            windowSeconds: 5 * 60 * 60
        )
        let secondary = self.usageWindow(
            fraction: self.doubleValue(payload["per1WeekPercentage"]),
            resetValue: payload["per1WeekResetTime"],
            windowSeconds: 7 * 24 * 60 * 60
        )

        guard primary != nil || secondary != nil else {
            throw ProviderErrorState.endpointError("No active QwenCloud Individual Token Plan")
        }
        return ParsedUsage(primary: primary, secondary: secondary)
    }

    private static func usagePayload(from root: [String: Any]) -> [String: Any]? {
        if self.containsUsageFields(root) {
            return root
        }
        guard let data = self.dictionaryValue(root["data"]) else { return nil }
        if self.containsUsageFields(data) {
            return data
        }
        if let nested = self.dictionaryValue(data["data"]), self.containsUsageFields(nested) {
            return nested
        }
        return nil
    }

    private static func containsUsageFields(_ object: [String: Any]) -> Bool {
        object["per5HourPercentage"] != nil || object["per1WeekPercentage"] != nil
    }

    private static func dictionaryValue(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        guard let string = value as? String,
              let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    private static func usageWindow(fraction: Double?, resetValue: Any?, windowSeconds: Int) -> UsageWindow? {
        guard let fraction, fraction.isFinite else { return nil }
        let usedPercent = fraction * 100
        return UsageWindow(
            usedPercent: max(0, min(100, usedPercent)),
            resetAt: self.dateValue(resetValue),
            windowSeconds: windowSeconds
        )
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        if let timestamp = self.doubleValue(value) {
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: text)
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func errorState(code: String?, message: String?) -> ProviderErrorState {
        let detail = [code, message]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ": ")
        let lowered = detail.lowercased()

        if lowered.contains("consoleneedlogin")
            || lowered.contains("need login")
            || lowered.contains("unauthorized")
            || lowered.contains("401")
            || lowered.contains("403")
        {
            return .authNeeded
        }
        if lowered.contains("throttl") || lowered.contains("rate limit") || lowered.contains("too many") {
            return .rateLimited(detail.isEmpty ? "QwenCloud request rate limited" : detail, retryAfter: nil)
        }
        return .endpointError(detail.isEmpty ? "QwenCloud usage request failed" : detail)
    }

    #if DEBUG
    static func decodeUsageResponse(_ data: Data) throws -> (primary: UsageWindow?, secondary: UsageWindow?) {
        let result = try self.parseUsageResponse(data)
        return (result.primary, result.secondary)
    }
    #endif
}
