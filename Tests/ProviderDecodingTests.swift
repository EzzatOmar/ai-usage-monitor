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
                { "modelId": "gemini-2.5-flash", "remainingFraction": 0.70, "resetTime": "2030-01-01T10:00:00Z" },
                { "modelId": "gemini-2.5-flash-lite", "remainingFraction": 0.85, "resetTime": "2030-01-02T10:00:00Z" },
                { "modelId": "gemini-3-flash-preview", "remainingFraction": 0.50, "resetTime": "2030-01-01T10:00:00Z" },
                { "modelId": "gemini-3-pro-preview", "remainingFraction": 0.60, "resetTime": "2030-01-01T10:00:00Z" }
              ]
            }
            """.utf8
        )

        let (primary, secondary, modelWindows) = try GeminiClient.decodeQuota(data)

        // Primary = most-used pro model (gemini-2.5-pro at 60% used) - Aggregates still include all models
        XCTAssertEqual(primary ?? 0, 60, accuracy: 0.0001)
        // Secondary = most-used flash model (gemini-3-flash-preview at 50% used)
        XCTAssertEqual(secondary ?? 0, 50, accuracy: 0.0001)

        // Only gemini-3 models should be in modelWindows
        XCTAssertEqual(modelWindows.count, 2)

        // Verify each model is present with correct usage
        let byModel = Dictionary(uniqueKeysWithValues: modelWindows.map { ($0.modelId, $0.window) })
        XCTAssertNil(byModel["gemini-2.5-pro"])
        XCTAssertNil(byModel["gemini-2.5-flash"])
        XCTAssertNil(byModel["gemini-2.5-flash-lite"])
        XCTAssertEqual(byModel["gemini-3-flash-preview"]?.usedPercent ?? 0, 50, accuracy: 0.0001)
        XCTAssertEqual(byModel["gemini-3-pro-preview"]?.usedPercent ?? 0, 40, accuracy: 0.0001)
    }

    func test_cerebrasParseRateLimitHeaders() throws {
        let url = URL(string: "https://api.cerebras.ai/v1/models")!
        let http = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "x-ratelimit-limit-tokens-day": "24000000",
                "x-ratelimit-remaining-tokens-day": "18000000",
                "x-ratelimit-reset-tokens-day": "3600",
            ]
        )!

        let now = Date()
        let result = CerebrasClient.parseRateLimitHeaders(http, now: now)

        // Daily: 6M used / 24M limit = 25% used
        XCTAssertNotNil(result.primary)
        XCTAssertEqual(result.primary!.usedPercent, 25, accuracy: 0.001)
        XCTAssertEqual(result.primary!.windowSeconds, 86400)
        XCTAssertNotNil(result.primary!.resetAt)
        XCTAssertEqual(result.primary!.resetAt!.timeIntervalSince(now), 3600, accuracy: 1)

        // No secondary window (no weekly limit)
        XCTAssertNil(result.secondary)

        XCTAssertEqual(result.accountLabel, "Day: 6000000/24000000 tokens")
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

    func test_minimaxDecodeUsage() throws {
        let data = Data(
            """
            {
                "model_remains": [
                    {
                        "start_time": 1771027200000,
                        "end_time": 1771045200000,
                        "remains_time": 17452643,
                        "current_interval_total_count": 4500,
                        "current_interval_usage_count": 255,
                        "model_name": "MiniMax-M2"
                    }
                ],
                "base_resp": {
                    "status_code": 0,
                    "status_msg": "success"
                }
            }
            """.utf8
        )

        let (primary, accountLabel) = try MinimaxClient.decodeUsageResponse(data)

        XCTAssertNotNil(primary)
        XCTAssertEqual(primary!.usedPercent, 94.33, accuracy: 0.1)
        XCTAssertEqual(accountLabel, "MiniMax-M2: 4245/4500 prompts")
    }

    func test_kimiDecodeUsage_weeklyAndFiveHour() throws {
        let data = Data(
            """
            {
              "usage": {
                "name": "Weekly limit",
                "used": 320,
                "limit": 2048,
                "resetAt": "2030-01-08T10:00:00Z"
              },
              "limits": [
                {
                  "name": "5h token quota",
                  "window": { "duration": 300, "timeUnit": "MINUTE" },
                  "detail": {
                    "name": "5h token quota",
                    "used": 180,
                    "limit": 1200,
                    "resetAt": "2030-01-01T15:00:00Z"
                  }
                },
                {
                  "name": "Weekly limit",
                  "window": { "duration": 7, "timeUnit": "DAY" },
                  "detail": {
                    "name": "Weekly limit",
                    "used": 320,
                    "limit": 2048,
                    "resetAt": "2030-01-08T10:00:00Z"
                  }
                }
              ]
            }
            """.utf8
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let (primary, secondary, accountLabel) = try KimiClient.decodeUsageResponse(data, now: now)

        XCTAssertNotNil(primary)
        XCTAssertNotNil(secondary)
        XCTAssertEqual(primary!.windowSeconds, 300 * 60)
        XCTAssertEqual(secondary!.windowSeconds, 7 * 24 * 3600)
        XCTAssertEqual(primary!.usedPercent, 15, accuracy: 0.001)
        XCTAssertEqual(secondary!.usedPercent, 15.625, accuracy: 0.001)
        XCTAssertEqual(accountLabel, "Kimi Code: 320/2048 requests")
    }

    func test_kimiDecodeUsage_stringNumbersFromAPI() throws {
        let data = Data(
            """
            {
              "user": {
                "userId": "u1"
              },
              "usage": {
                "limit": "100",
                "used": "15",
                "remaining": "85",
                "resetTime": "2026-02-25T11:47:50.533528Z"
              },
              "limits": [
                {
                  "window": {
                    "duration": 300,
                    "timeUnit": "TIME_UNIT_MINUTE"
                  },
                  "detail": {
                    "limit": "100",
                    "used": "1",
                    "remaining": "99",
                    "resetTime": "2026-02-22T00:47:50.533528Z"
                  }
                }
              ]
            }
            """.utf8
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let (primary, secondary, accountLabel) = try KimiClient.decodeUsageResponse(data, now: now)

        XCTAssertNotNil(primary)
        XCTAssertNotNil(secondary)
        XCTAssertEqual(primary!.windowSeconds, 300 * 60)
        XCTAssertEqual(primary!.usedPercent, 1, accuracy: 0.001)
        XCTAssertEqual(secondary!.windowSeconds, 7 * 24 * 3600)
        XCTAssertEqual(secondary!.usedPercent, 15, accuracy: 0.001)
        XCTAssertEqual(accountLabel, "Kimi Code: 15/100 requests")
    }
}
