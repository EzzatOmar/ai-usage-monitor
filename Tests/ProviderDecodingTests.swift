import XCTest
@testable import AIUsageMonitor

final class ProviderDecodingTests: XCTestCase {
    func test_codexDecodePrimaryAndSecondary() throws {
        let data = Data(
            """
            {
              "rate_limit": {
                "primary_window": { "used_percent": 35, "reset_at": 2000000000, "limit_window_seconds": 18000 },
                "secondary_window": { "used_percent": 60, "reset_at": 2000003600, "limit_window_seconds": 604800 }
              }
            }
            """.utf8
        )

        let (primary, secondary) = try CodexClient.decodeUsageResponse(data)
        XCTAssertEqual(primary, 35)
        XCTAssertEqual(secondary, 60)
    }

    func test_claudeDecodeWindows() throws {
        let data = Data(
            """
            {
              "five_hour": { "utilization": 45.0, "resets_at": "2030-01-01T10:00:00Z" },
              "seven_day": { "utilization": 75.0, "resets_at": "2030-01-07T10:00:00Z" }
            }
            """.utf8
        )

        let (fiveHour, sevenDay) = try ClaudeClient.decodeUsageResponse(data)
        XCTAssertEqual(fiveHour, 45.0)
        XCTAssertEqual(sevenDay, 75.0)
    }

    func test_geminiDecodeQuota() throws {
        let data = Data(
            """
            {
              "buckets": [
                { "modelId": "gemini-2.5-pro", "remainingFraction": 0.40, "resetTime": "2030-01-01T10:00:00Z" },
                { "modelId": "gemini-2.5-flash", "remainingFraction": 0.70, "resetTime": "2030-01-01T10:00:00Z" }
              ]
            }
            """.utf8
        )

        let (primary, secondary) = try GeminiClient.decodeQuota(data)
        XCTAssertEqual(primary ?? 0, 60, accuracy: 0.0001)
        XCTAssertEqual(secondary ?? 0, 30, accuracy: 0.0001)
    }

    func test_cerebrasParseRateLimitHeaders() throws {
        let url = URL(string: "https://api.cerebras.ai/v1/models")!
        let http = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "x-ratelimit-limit-requests-day": "1000",
                "x-ratelimit-remaining-requests-day": "750",
                "x-ratelimit-reset-requests-day": "3600",
                "x-ratelimit-limit-tokens-minute": "100000",
                "x-ratelimit-remaining-tokens-minute": "90000",
                "x-ratelimit-reset-tokens-minute": "30",
            ]
        )!

        let now = Date()
        let result = CerebrasClient.parseRateLimitHeaders(http, now: now)

        // Daily: 250 used / 1000 limit = 25% used
        XCTAssertNotNil(result.primary)
        XCTAssertEqual(result.primary!.usedPercent, 25, accuracy: 0.001)
        XCTAssertEqual(result.primary!.windowSeconds, 86400)
        XCTAssertNotNil(result.primary!.resetAt)
        XCTAssertEqual(result.primary!.resetAt!.timeIntervalSince(now), 3600, accuracy: 1)

        // Per-minute: 10000 used / 100000 limit = 10% used
        XCTAssertNotNil(result.secondary)
        XCTAssertEqual(result.secondary!.usedPercent, 10, accuracy: 0.001)
        XCTAssertEqual(result.secondary!.windowSeconds, 60)

        XCTAssertEqual(result.accountLabel, "Day: 250/1000 reqs")
    }

    func test_cerebrasParseRateLimitHeaders_noHeaders() throws {
        let url = URL(string: "https://api.cerebras.ai/v1/models")!
        let http = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!

        let result = CerebrasClient.parseRateLimitHeaders(http, now: Date())
        XCTAssertNil(result.primary)
        XCTAssertNil(result.secondary)
        XCTAssertNil(result.accountLabel)
    }
}
