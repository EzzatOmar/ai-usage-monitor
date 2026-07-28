import Foundation

protocol CursorUsageTransport: Sendable {
    func fetchUsagePayload(now: Date) async throws -> Data
}

struct CursorClient: ProviderClient {
    let providerID: ProviderID = .cursor
    private let transport: any CursorUsageTransport

    init() {
        self.transport = CursorDashboardTransport.shared
    }

    init(transport: any CursorUsageTransport) {
        self.transport = transport
    }

    func fetchUsage(now: Date, mode _: UsageRefreshMode) async -> ProviderUsageResult {
        do {
            let data = try await self.transport.fetchUsagePayload(now: now)
            let usage = try Self.parseUsageResponse(data)
            return ProviderUsageResult(
                provider: .cursor,
                primaryWindow: usage.api,
                secondaryWindow: usage.auto,
                accountLabel: usage.accountLabel,
                lastUpdated: now
            )
        } catch let error as ProviderErrorState {
            return ProviderUsageResult(
                provider: .cursor,
                lastUpdated: now,
                errorState: error
            )
        } catch {
            return ProviderUsageResult(
                provider: .cursor,
                lastUpdated: now,
                errorState: .networkError(error.localizedDescription)
            )
        }
    }

    private struct ParsedUsage {
        let api: UsageWindow?
        let auto: UsageWindow?
        let accountLabel: String?
    }

    private static func parseUsageResponse(_ data: Data) throws -> ParsedUsage {
        let rawObject: Any
        do {
            rawObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProviderErrorState.parseError("Invalid Cursor usage payload")
        }

        guard let root = rawObject as? [String: Any] else {
            throw ProviderErrorState.parseError("Invalid Cursor usage payload")
        }

        let plan = self.dictionaryValue(root["planUsage"])
            ?? self.dictionaryValue(self.dictionaryValue(root["individualUsage"])?["plan"])
        let isUnlimited = self.boolValue(root["isUnlimited"]) ?? false
        let resetAt = self.dateValue(root["billingCycleEnd"])
        let cycleStart = self.dateValue(root["billingCycleStart"])
        let windowSeconds: Int?
        if let cycleStart, let resetAt, resetAt > cycleStart {
            windowSeconds = Int(resetAt.timeIntervalSince(cycleStart))
        } else {
            windowSeconds = nil
        }

        let apiPercent = self.percentageValue(plan?["apiPercentUsed"])
            ?? self.percentageFromUsedAndLimit(plan)
        let autoPercent = self.percentageValue(plan?["autoPercentUsed"])
        let api = apiPercent.map {
            UsageWindow(usedPercent: $0, resetAt: resetAt, windowSeconds: windowSeconds)
        }
        let auto = autoPercent.map {
            UsageWindow(usedPercent: $0, resetAt: resetAt, windowSeconds: windowSeconds)
        }

        let membership = self.stringValue(root["membershipType"])
        let accountLabel: String?
        if isUnlimited {
            accountLabel = [membership, "Unlimited"]
                .compactMap { self.trimmed($0) }
                .joined(separator: " · ")
        } else {
            accountLabel = membership
        }

        guard isUnlimited || api != nil || auto != nil else {
            throw ProviderErrorState.endpointError(
                "Cursor returned no individual quota data. Sign into Cursor again or open its usage dashboard."
            )
        }
        return ParsedUsage(api: api, auto: auto, accountLabel: accountLabel)
    }

    private static func percentageFromUsedAndLimit(_ plan: [String: Any]?) -> Double? {
        guard let plan else { return nil }
        let used = self.doubleValue(plan["totalSpend"]) ?? self.doubleValue(plan["used"])
        guard let used,
              let limit = self.doubleValue(plan["limit"]),
              limit > 0
        else {
            return nil
        }
        return max(0, min(100, used / limit * 100))
    }

    private static func percentageValue(_ value: Any?) -> Double? {
        guard let value = self.doubleValue(value), value.isFinite else { return nil }
        return max(0, min(100, value))
    }

    private static func dictionaryValue(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        return nil
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
        if let timestamp = self.doubleValue(value), timestamp.isFinite {
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }
        guard let text = self.stringValue(value) else { return nil }
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
        self.trimmed(value as? String)
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    #if DEBUG
    static func decodeUsageResponse(
        _ data: Data
    ) throws -> (api: UsageWindow?, auto: UsageWindow?, accountLabel: String?) {
        let result = try self.parseUsageResponse(data)
        return (result.api, result.auto, result.accountLabel)
    }
    #endif
}
