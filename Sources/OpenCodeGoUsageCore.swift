import Foundation

/// Pure decoding of the Go usage API; never estimates billing windows locally.
enum OpenCodeGoUsageCore {
    static func decodeUsage(_ data: Data, now: Date) throws -> ProviderUsageResult {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ProviderErrorState.parseError("OpenCode Go returned an invalid usage response.")
        }
        return try ProviderUsageResult(
            provider: .openCodeGo,
            primaryWindow: self.window(response.usage.rolling, seconds: 18_000),
            secondaryWindow: self.window(response.usage.weekly, seconds: 604_800),
            tertiaryWindow: self.window(response.usage.monthly, seconds: nil),
            lastUpdated: now
        )
    }

    static func selectAPIKey(stored: String?, environment: String?, authData: Data?) -> String? {
        for value in [stored, environment] {
            if let key = self.nonempty(value) { return key }
        }
        guard let authData,
              let root = try? JSONDecoder().decode(AuthFile.self, from: authData),
              let credential = root.go, credential.type == "api"
        else { return nil }
        return self.nonempty(credential.key)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func window(_ value: Window, seconds: Int?) throws -> UsageWindow {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var reset = formatter.date(from: value.resetsAt)
        if reset == nil {
            formatter.formatOptions = [.withInternetDateTime]
            reset = formatter.date(from: value.resetsAt)
        }
        guard value.percent.isFinite, (0...100).contains(value.percent), let reset else {
            throw ProviderErrorState.parseError("OpenCode Go returned invalid quota values or reset timestamps.")
        }
        // A depleted quota is valid usage data, not an HTTP rate-limit failure.
        return UsageWindow(usedPercent: value.percent, resetAt: reset, windowSeconds: seconds)
    }

    private struct Response: Decodable {
        let usage: Windows
    }

    private struct Windows: Decodable {
        let rolling: Window
        let weekly: Window
        let monthly: Window
    }

    private struct Window: Decodable {
        let status: Status
        let percent: Double
        let resetsAt: String
    }

    private enum Status: String, Decodable {
        case ok
        case rateLimited = "rate-limited"
    }

    private struct AuthFile: Decodable {
        let go: Credential?

        enum CodingKeys: String, CodingKey {
            case go = "opencode-go"
        }
    }

    private struct Credential: Decodable {
        let type: String
        let key: String?
    }
}
