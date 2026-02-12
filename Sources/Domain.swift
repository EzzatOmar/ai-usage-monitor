import Foundation

enum ProviderID: String, CaseIterable, Sendable {
    case claude = "Claude"
    case codex = "Codex"
    case gemini = "Gemini"
    case zai = "Z.AI"
}

enum ProviderErrorState: Error, Sendable, Equatable {
    case authNeeded
    case tokenExpired
    case endpointError(String)
    case parseError(String)
    case networkError(String)

    var badgeText: String {
        switch self {
        case .authNeeded: return "Auth needed"
        case .tokenExpired: return "Token expired"
        case .endpointError(let message):
            let lowered = message.lowercased()
            if lowered.contains("401") || lowered.contains("403") || lowered.contains("rejected") || lowered.contains("invalid") {
                return "Auth needed"
            }
            return "API error"
        case .parseError: return "Parse error"
        case .networkError: return "Network error"
        }
    }

    var detailText: String? {
        switch self {
        case .authNeeded:
            return "Add credentials to fetch usage"
        case .tokenExpired:
            return "Token expired, update Claude auth"
        case .endpointError(let message):
            return message
        case .parseError(let message):
            return message
        case .networkError(let message):
            return message
        }
    }
}

struct UsageWindow: Sendable, Equatable {
    let usedPercent: Double
    let resetAt: Date?
    let windowSeconds: Int?

    var remainingPercent: Double {
        max(0, min(100, 100 - self.usedPercent))
    }
}

struct ProviderUsageResult: Sendable, Equatable {
    let provider: ProviderID
    let primaryWindow: UsageWindow?
    let secondaryWindow: UsageWindow?
    let accountLabel: String?
    let lastUpdated: Date
    let errorState: ProviderErrorState?
    let isStale: Bool
}

struct UsageSnapshot: Sendable, Equatable {
    var results: [ProviderUsageResult]
    var lastUpdated: Date?
    var isRefreshing: Bool

    static let empty = UsageSnapshot(results: [], lastUpdated: nil, isRefreshing: false)

    var minimumRemainingPercent: Double? {
        self.results.compactMap { $0.primaryWindow?.remainingPercent }.min()
    }
}

enum RelativeTimeFormatter {
    private static let formatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.allowedUnits = [.day, .hour, .minute]
        f.maximumUnitCount = 2
        return f
    }()

    static func resetText(_ date: Date?) -> String {
        guard let date else { return "Reset unknown" }
        if date <= Date() { return "Resets soon" }
        let value = self.formatter.string(from: Date(), to: date) ?? "soon"
        return "Resets in \(value)"
    }

    static func lastUpdatedText(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let value = self.formatter.string(from: date, to: Date()) ?? "just now"
        return "\(value) ago"
    }
}
