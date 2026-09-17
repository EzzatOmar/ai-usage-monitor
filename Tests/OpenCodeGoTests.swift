import XCTest
@testable import AIUsageMonitor

final class OpenCodeGoTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_632_000)
    private static let fixture = Data("""
    {"usage":{
      "rolling":{"status":"ok","percent":12,"resetsAt":"2026-09-17T12:00:00.123Z"},
      "weekly":{"status":"ok","percent":45.5,"resetsAt":"2026-09-21T00:00:00Z"},
      "monthly":{"status":"rate-limited","percent":100,"resetsAt":"2026-10-04T14:30:00.000Z"}
    }}
    """.utf8)

    func test_decodesActualUpstreamSchemaAndAllResetDates() throws {
        let result = try OpenCodeGoUsageCore.decodeUsage(Self.fixture, now: self.now)
        XCTAssertEqual(result.provider, .openCodeGo)
        XCTAssertEqual(result.primaryWindow?.remainingPercent, 88)
        XCTAssertEqual(result.secondaryWindow?.remainingPercent, 54.5)
        XCTAssertEqual(result.tertiaryWindow?.remainingPercent, 0)
        XCTAssertEqual(result.primaryWindow?.windowSeconds, 18_000)
        XCTAssertEqual(result.secondaryWindow?.windowSeconds, 604_800)
        XCTAssertNil(result.tertiaryWindow?.windowSeconds)
        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(result.secondaryWindow?.resetAt, formatter.date(from: "2026-09-21T00:00:00Z"))
        XCTAssertEqual(result.tertiaryWindow?.resetAt, formatter.date(from: "2026-10-04T14:30:00Z"))
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(result.primaryWindow?.resetAt, formatter.date(from: "2026-09-17T12:00:00.123Z"))
        XCTAssertEqual(result.lastUpdated, self.now)
        XCTAssertNil(result.errorState, "Quota exhaustion is successful usage data, not a retryable error")
    }

    func test_rejectsIncompleteMalformedAndOutOfRangeResponses() {
        let source = String(decoding: Self.fixture, as: UTF8.self)
        let invalid = [
            "{}", "<html>unavailable</html>",
            source.replacingOccurrences(of: "\"monthly\"", with: "\"unknown\""),
            source.replacingOccurrences(of: "\"percent\":12", with: "\"percent\":-1"),
            source.replacingOccurrences(of: "\"percent\":12", with: "\"percent\":101"),
            source.replacingOccurrences(of: "\"percent\":12", with: "\"percent\":null"),
            source.replacingOccurrences(of: "\"percent\":12", with: "\"percent\":\"12\""),
            source.replacingOccurrences(of: "2026-09-17T12:00:00.123Z", with: "not-a-date"),
            source.replacingOccurrences(of: "\"status\":\"ok\"", with: "\"status\":\"unknown\""),
        ]
        for body in invalid {
            XCTAssertThrowsError(try OpenCodeGoUsageCore.decodeUsage(Data(body.utf8), now: self.now)) { error in
                guard case .parseError = error as? ProviderErrorState else {
                    return XCTFail("Expected a safe parse error")
                }
            }
        }
        let zero = source.replacingOccurrences(of: "\"percent\":12", with: "\"percent\":0")
        XCTAssertEqual(try OpenCodeGoUsageCore.decodeUsage(Data(zero.utf8), now: self.now).primaryWindow?.remainingPercent, 100)
    }

    func test_credentialPriorityTrimmingAndProviderIsolation() {
        let auth = Data(#"{"opencode-go":{"type":"api","key":" local-key\n"},"unrelated":42}"#.utf8)
        XCTAssertEqual(OpenCodeGoUsageCore.selectAPIKey(stored: " saved ", environment: "env", authData: auth), "saved")
        XCTAssertEqual(OpenCodeGoUsageCore.selectAPIKey(stored: " \n", environment: " env\n", authData: auth), "env")
        XCTAssertEqual(OpenCodeGoUsageCore.selectAPIKey(stored: nil, environment: " ", authData: auth), "local-key")
        for json in [
            #"{"opencode":{"type":"api","key":"zen-only"}}"#,
            #"{"opencode-go":{"type":"oauth","key":"not-api"}}"#,
            #"{"opencode-go":{"type":"api","key":" "}}"#,
            "{}", "bad-json",
        ] {
            XCTAssertNil(OpenCodeGoUsageCore.selectAPIKey(stored: nil, environment: nil, authData: Data(json.utf8)))
        }
    }

    func test_authPathHonorsXDGWithoutChangingOtherAuthFiles() {
        let home = URL(fileURLWithPath: "/test/home")
        XCTAssertEqual(LocalPaths.openCodeAuthPath(env: [:], home: home).path, "/test/home/.local/share/opencode/auth.json")
        XCTAssertEqual(LocalPaths.openCodeAuthPath(env: ["XDG_DATA_HOME": "/custom/data"], home: home).path, "/custom/data/opencode/auth.json")
        for value in ["", "  ", "relative"] {
            XCTAssertEqual(LocalPaths.openCodeAuthPath(env: ["XDG_DATA_HOME": value], home: home).path, "/test/home/.local/share/opencode/auth.json")
        }
    }

    func test_clientUsesOnlyReadOnlyEndpointWithBearerKey() async {
        let client = OpenCodeGoClient(loadAPIKey: { " test-key \n" }, transport: { request in
            XCTAssertEqual(request.url?.absoluteString, "https://opencode.ai/zen/go/v1/usage")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            return (Self.fixture, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = await client.fetchUsage(now: self.now, mode: .manual)
        XCTAssertNil(result.errorState)
        XCTAssertEqual(result.tertiaryWindow?.usedPercent, 100)
    }

    func test_missingKeyDoesNotCallTransport() async {
        for key: String? in [nil, "", " \n"] {
            let client = OpenCodeGoClient(loadAPIKey: { key }, transport: { _ in
                XCTFail("Must not request without credentials")
                throw URLError(.badURL)
            })
            let result = await client.fetchUsage(now: self.now, mode: .manual)
            XCTAssertEqual(result.errorState, .authNeeded)
        }
    }

    func test_httpErrorsAreClassifiedWithoutExposingBodies() async {
        let cases: [(Int, String, ProviderErrorState)] = [
            (401, "secret", .tokenExpired),
            (403, #"{"error":{"type":"EntitlementError","message":"secret"}}"#, .endpointError("This key requires an active OpenCode Go subscription.")),
            (403, "<html>secret</html>", .endpointError("OpenCode Go denied access (HTTP 403). Check the key or try again later.")),
            (429, "secret", .rateLimited("OpenCode Go usage API is rate limited.", retryAfter: 30)),
            (500, "secret", .endpointError("OpenCode Go usage request failed (HTTP 500).")),
            (404, "secret", .endpointError("OpenCode Go usage request failed (HTTP 404).")),
            (200, "secret", .parseError("OpenCode Go returned an invalid usage response.")),
        ]
        for (status, body, expected) in cases {
            let client = OpenCodeGoClient(loadAPIKey: { "secret" }, transport: { request in
                (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "30"])!)
            })
            let result = await client.fetchUsage(now: self.now, mode: .manual)
            XCTAssertEqual(result.errorState, expected)
            XCTAssertNil(result.primaryWindow)
            XCTAssertNil(result.tertiaryWindow)
            XCTAssertFalse(result.errorState?.detailText?.contains("secret") ?? true)
        }
    }

    func test_networkErrorDoesNotExposeCredential() async {
        let client = OpenCodeGoClient(loadAPIKey: { "secret" }, transport: { _ in
            throw NSError(domain: "secret", code: 1, userInfo: [NSLocalizedDescriptionKey: "secret"])
        })
        let result = await client.fetchUsage(now: self.now, mode: .manual)
        guard case .networkError(let detail) = result.errorState else { return XCTFail("Expected network error") }
        XCTAssertFalse(detail.contains("secret"))
    }

    func test_goTightestWindowContributesOnlyWhenEnabled() throws {
        let go = try OpenCodeGoUsageCore.decodeUsage(Self.fixture, now: self.now)
        let other = ProviderUsageResult(
            provider: .codex,
            primaryWindow: UsageWindow(usedPercent: 10, resetAt: nil, windowSeconds: nil),
            secondaryWindow: UsageWindow(usedPercent: 100, resetAt: nil, windowSeconds: nil),
            lastUpdated: self.now
        )
        XCTAssertEqual(other.menuRemainingPercent, 90, "Existing providers keep primary-window behavior")
        XCTAssertEqual(UsageSnapshot(results: [go, other], lastUpdated: self.now, isRefreshing: false).minimumRemainingPercent, 0)
        XCTAssertEqual(ProviderSelection.minimumRemainingPercent(results: [go, other], providerEnabled: [.openCodeGo: false]), 90)
        XCTAssertEqual(ProviderSelection.minimumRemainingPercent(results: [go, other], activeClientIDs: [go.id]), 0)
        XCTAssertEqual(ProviderSelection.minimumRemainingPercent(results: [go, other], activeClientIDs: [other.id]), 90)
        for (primary, weekly, monthly) in [(99.0, 10.0, 20.0), (10, 99, 20), (10, 20, 99)] {
            let result = ProviderUsageResult(
                provider: .openCodeGo,
                primaryWindow: UsageWindow(usedPercent: primary, resetAt: nil, windowSeconds: nil),
                secondaryWindow: UsageWindow(usedPercent: weekly, resetAt: nil, windowSeconds: nil),
                tertiaryWindow: UsageWindow(usedPercent: monthly, resetAt: nil, windowSeconds: nil),
                lastUpdated: self.now
            )
            XCTAssertEqual(result.menuRemainingPercent, 1)
        }
    }
}
