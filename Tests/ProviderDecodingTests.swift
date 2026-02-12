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
              "five_hour": { "utilization": 0.45, "resets_at": "2030-01-01T10:00:00Z" },
              "seven_day": { "utilization": 0.75, "resets_at": "2030-01-07T10:00:00Z" }
            }
            """.utf8
        )

        let (fiveHour, sevenDay) = try ClaudeClient.decodeUsageResponse(data)
        XCTAssertEqual(fiveHour, 0.45)
        XCTAssertEqual(sevenDay, 0.75)
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
}
