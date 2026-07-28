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

    func test_cursorDecodeCurrentPeriodUsage() throws {
        let data = Data(
            """
            {
              "enabled": true,
              "membershipType": "ultra",
              "billingCycleStart": "2030-06-04T10:00:00.000Z",
              "billingCycleEnd": "2030-07-04T10:00:00.000Z",
              "planUsage": {
                "autoPercentUsed": 36.7,
                "apiPercentUsed": 12.4,
                "totalPercentUsed": 24.2,
                "totalSpend": 14680,
                "limit": 40000,
                "remaining": 25320
              }
            }
            """.utf8
        )

        let (api, auto, accountLabel) = try CursorClient.decodeUsageResponse(data)

        XCTAssertEqual(api?.usedPercent ?? -1, 12.4, accuracy: 0.0001)
        XCTAssertEqual(auto?.usedPercent ?? -1, 36.7, accuracy: 0.0001)
        XCTAssertEqual(api?.windowSeconds, 30 * 24 * 60 * 60)
        XCTAssertEqual(api?.resetAt, auto?.resetAt)
        XCTAssertEqual(accountLabel, "ultra")
    }

    func test_cursorDecodeUsageSummaryFallbackShape() throws {
        let data = Data(
            """
            {
              "billingCycleStart": "2030-04-02T14:11:55Z",
              "billingCycleEnd": "2030-05-02T14:11:55Z",
              "membershipType": "pro",
              "isUnlimited": false,
              "individualUsage": {
                "plan": {
                  "enabled": true,
                  "used": 2000,
                  "limit": 2000,
                  "remaining": 0,
                  "autoPercentUsed": -4,
                  "apiPercentUsed": 120
                }
              }
            }
            """.utf8
        )

        let (api, auto, accountLabel) = try CursorClient.decodeUsageResponse(data)

        XCTAssertEqual(api?.usedPercent, 100)
        XCTAssertEqual(auto?.usedPercent, 0)
        XCTAssertEqual(accountLabel, "pro")
    }

    func test_cursorDecodeFallsBackToUsedAndLimit() throws {
        let data = Data(
            """
            {
              "billingCycleEnd": 2000000000000,
              "individualUsage": {
                "plan": {
                  "used": "25",
                  "limit": 100
                }
              }
            }
            """.utf8
        )

        let (api, auto, _) = try CursorClient.decodeUsageResponse(data)
        XCTAssertEqual(api?.usedPercent, 25)
        XCTAssertNil(auto)
        XCTAssertEqual(api?.resetAt?.timeIntervalSince1970, 2_000_000_000)
    }

    func test_cursorDecodeRejectsResponsesWithoutQuotaFields() {
        let data = Data(#"{"billingCycleEnd":"2030-05-02T14:11:55Z"}"#.utf8)

        XCTAssertThrowsError(try CursorClient.decodeUsageResponse(data)) { error in
            guard case .endpointError(let message) = error as? ProviderErrorState else {
                return XCTFail("Expected endpointError")
            }
            XCTAssertTrue(message.contains("no individual quota data"))
        }
    }

    func test_cursorBuildsDashboardCookieFromLocalJWT() throws {
        let token = self.makeJWT(payload: [
            "sub": "github|user_01CURSOR",
            "exp": 2_000_000_000,
            "type": "session",
        ])
        let session = try CursorSessionReader.session(
            from: token,
            now: Date(timeIntervalSince1970: 1_900_000_000)
        )

        XCTAssertEqual(
            session.cookieValue,
            "user_01CURSOR%3A%3A\(token)"
        )
    }

    func test_cursorRejectsExpiredLocalJWT() {
        let token = self.makeJWT(payload: [
            "sub": "user_01CURSOR",
            "exp": 1_800_000_000,
        ])

        XCTAssertThrowsError(
            try CursorSessionReader.session(
                from: token,
                now: Date(timeIntervalSince1970: 1_900_000_000)
            )
        ) { error in
            XCTAssertEqual(error as? ProviderErrorState, .tokenExpired)
        }
    }

    func test_cursorDashboardRequestsUseSessionCookieAndNoInferenceEndpoint() {
        let session = CursorSession(cookieValue: "user_01CURSOR%3A%3Ajwt")
        let current = CursorDashboardTransport.makeCurrentPeriodRequest(session: session)
        let fallback = CursorDashboardTransport.makeUsageSummaryRequest(session: session)

        XCTAssertEqual(
            current.value(forHTTPHeaderField: "Cookie"),
            "WorkosCursorSessionToken=user_01CURSOR%3A%3Ajwt"
        )
        XCTAssertEqual(current.httpMethod, "POST")
        XCTAssertEqual(current.url?.host, "cursor.com")
        XCTAssertEqual(current.url?.path, "/api/dashboard/get-current-period-usage")
        XCTAssertEqual(current.value(forHTTPHeaderField: "Origin"), "https://cursor.com")
        XCTAssertEqual(current.httpBody, Data("{}".utf8))

        XCTAssertEqual(fallback.httpMethod, "GET")
        XCTAssertEqual(fallback.url?.path, "/api/usage-summary")
        XCTAssertNil(fallback.value(forHTTPHeaderField: "Origin"))
        XCTAssertNil(fallback.httpBody)

        for request in [current, fallback] {
            XCTAssertFalse(request.url?.absoluteString.contains("chat") ?? true)
            XCTAssertFalse(request.url?.absoluteString.contains("completion") ?? true)
        }
    }

    func test_cursorHTTPErrorMapping() {
        let url = URL(string: "https://cursor.com/api/usage-summary")!
        let unauthorized = HTTPURLResponse(
            url: url,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!
        let throttled = HTTPURLResponse(
            url: url,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "30"]
        )!

        XCTAssertEqual(
            CursorDashboardTransport.errorState(for: unauthorized),
            .tokenExpired
        )
        XCTAssertEqual(
            CursorDashboardTransport.errorState(for: throttled),
            .rateLimited("Cursor dashboard request rate limited", retryAfter: 30)
        )
    }

    func test_qwenCloudDecodeFiveHourAndWeeklyWindows() throws {
        let data = Data(
            """
            {
              "successResponse": true,
              "data": {
                "per5HourPercentage": 0.25,
                "per5HourResetTime": 2000000000000,
                "per1WeekPercentage": "0.6",
                "per1WeekResetTime": "2033-05-18T03:33:20Z"
              }
            }
            """.utf8
        )

        let (primary, secondary) = try QwenCloudClient.decodeUsageResponse(data)

        XCTAssertEqual(primary?.usedPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(primary?.windowSeconds, 5 * 60 * 60)
        XCTAssertEqual(primary?.resetAt?.timeIntervalSince1970 ?? 0, 2_000_000_000, accuracy: 0.001)
        XCTAssertEqual(secondary?.usedPercent ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(secondary?.windowSeconds, 7 * 24 * 60 * 60)
        XCTAssertNotNil(secondary?.resetAt)
    }

    func test_qwenCloudDecodeNestedPayloadAndClamp() throws {
        let data = Data(
            """
            {
              "data": {
                "data": {
                  "per5HourPercentage": 1.4,
                  "per1WeekPercentage": -0.2
                }
              }
            }
            """.utf8
        )

        let (primary, secondary) = try QwenCloudClient.decodeUsageResponse(data)
        XCTAssertEqual(primary?.usedPercent, 100)
        XCTAssertEqual(secondary?.usedPercent, 0)
    }

    func test_qwenCloudDecodeMissingPlan() {
        let data = Data(#"{"successResponse":true,"data":{}}"#.utf8)

        XCTAssertThrowsError(try QwenCloudClient.decodeUsageResponse(data)) { error in
            XCTAssertEqual(
                error as? ProviderErrorState,
                .endpointError("No active QwenCloud Individual Token Plan")
            )
        }
    }

    func test_qwenCloudMapsThrottlingEnvelope() {
        let data = Data(
            #"{"successResponse":false,"code":"Throttling.User","message":"Too many requests"}"#.utf8
        )

        XCTAssertThrowsError(try QwenCloudClient.decodeUsageResponse(data)) { error in
            XCTAssertEqual(
                error as? ProviderErrorState,
                .rateLimited("Throttling.User: Too many requests", retryAfter: nil)
            )
        }
    }

    @MainActor
    func test_qwenCloudAPIKeyValidationUsesFreeModelsEndpoint() {
        let request = QwenCloudAPIKeyTransport.makeAPIKeyValidationRequest(apiKey: "sk-sp-test")

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.host, "token-plan.ap-southeast-1.maas.aliyuncs.com")
        XCTAssertEqual(request.url?.path, "/compatible-mode/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-sp-test")
        XCTAssertFalse(request.url?.absoluteString.contains("chat/completions") ?? true)
        XCTAssertNil(request.httpBody)
    }

    func test_qwenCloudLoadsIndividualKeyFromQwenSettings() {
        let data = Data(
            """
            {
              "env": {
                "BAILIAN_TOKEN_PLAN_API_KEY": "  sk-sp-individual-test  ",
                "DASHSCOPE_API_KEY": "sk-pay-as-you-go"
              }
            }
            """.utf8
        )

        XCTAssertEqual(
            AuthStore.qwenCloudTokenPlanAPIKey(fromSettings: data),
            "sk-sp-individual-test"
        )
    }

    func test_qwenCloudRejectsNonIndividualKeyFromQwenSettings() {
        let data = Data(#"{"env":{"BAILIAN_TOKEN_PLAN_API_KEY":"sk-pay-as-you-go"}}"#.utf8)
        XCTAssertNil(AuthStore.qwenCloudTokenPlanAPIKey(fromSettings: data))
    }

    func test_claudeRefreshPolicy_respectsCooldown() {
        var policy = ClaudeCLIRefreshPolicy(cooldown: 600, lastLaunchAt: nil)
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(policy.canLaunch(now: now))

        policy.markLaunch(at: now)
        XCTAssertFalse(policy.canLaunch(now: now.addingTimeInterval(599)))
        XCTAssertTrue(policy.canLaunch(now: now.addingTimeInterval(600)))
    }

    func test_claudeAutoRefreshTrigger_onlyForExpirations() {
        XCTAssertTrue(ClaudeClient.shouldTriggerAutoClaudeCLI(for: .tokenExpired))
        XCTAssertTrue(ClaudeClient.shouldTriggerAutoClaudeCLI(for: .endpointError("Token expired - run 'claude' in terminal to refresh")))
        XCTAssertTrue(ClaudeClient.shouldTriggerAutoClaudeCLI(for: .endpointError("Run 'claude' in terminal to refresh token")))

        XCTAssertFalse(ClaudeClient.shouldTriggerAutoClaudeCLI(for: .authNeeded))
        XCTAssertFalse(ClaudeClient.shouldTriggerAutoClaudeCLI(for: .rateLimited("HTTP 429", retryAfter: 1)))
        XCTAssertFalse(ClaudeClient.shouldTriggerAutoClaudeCLI(for: .networkError("offline")))
        XCTAssertFalse(ClaudeClient.shouldTriggerAutoClaudeCLI(for: .parseError("bad payload")))
    }

    func test_claudeUsesClaudeCLIUserAgentForAnthropicRequests() {
        XCTAssertEqual(ClaudeClient.anthropicUserAgent, "claude-cli/2.1.80")
    }

    func test_codexDecodeOpenCodeCredentials_extractsAccountIDFromJWT() throws {
        let token = makeJWT(payload: [
            "chatgpt_account_id": "acct_123"
        ])
        let data = Data(
            """
            {
              "openai": {
                "type": "oauth",
                "refresh": "refresh-token",
                "access": "\(token)",
                "expires": 1742561234567
              }
            }
            """.utf8
        )

        let credentials = try XCTUnwrap(CodexClient.decodeOpenCodeCredentials(data))
        XCTAssertEqual(credentials.access, token)
        XCTAssertEqual(credentials.refresh, "refresh-token")
        XCTAssertEqual(credentials.accountID, "acct_123")
        XCTAssertNotNil(credentials.expiresAt)
    }

    func test_codexExtractAccountIDFromOrganizationClaim() {
        let token = makeJWT(payload: [
            "organizations": [["id": "org_456"]]
        ])

        XCTAssertEqual(CodexClient.extractAccountIDForTests(token), "org_456")
    }

    func test_codexFallbackPolicy_advancesToOpenCodeForStalePrimaryAuth() {
        XCTAssertTrue(CodexClient.shouldTryNextCredentialForTests(.endpointError("Codex auth is stale (refresh token reused). Run 'codex login' and then refresh.")))
        XCTAssertTrue(CodexClient.shouldTryNextCredentialForTests(.tokenExpired))
        XCTAssertTrue(CodexClient.shouldTryNextCredentialForTests(.endpointError("Unauthorized: invalid_api_key")))
        XCTAssertFalse(CodexClient.shouldTryNextCredentialForTests(.rateLimited("HTTP 429", retryAfter: 1)))
    }

    private func makeJWT(payload: [String: Any]) -> String {
        let headerData = try! JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        return "\(headerData.base64URLEncodedString()).\(payloadData.base64URLEncodedString()).signature"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
