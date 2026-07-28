import Foundation
import SQLite3

struct CursorSession: Sendable, Equatable {
    let cookieValue: String
}

enum CursorSessionReader {
    private static let accessTokenKey = "cursorAuth/accessToken"

    static func loadSession(now: Date = Date()) throws -> CursorSession {
        if let override = self.trimmed(ProcessInfo.processInfo.environment["CURSOR_SESSION_TOKEN"]) {
            return try self.session(from: override, now: now)
        }

        var foundExpiredSession = false
        for token in self.localAccessTokens() {
            do {
                return try self.session(from: token, now: now)
            } catch ProviderErrorState.tokenExpired {
                foundExpiredSession = true
            } catch {
                continue
            }
        }

        if foundExpiredSession {
            throw ProviderErrorState.tokenExpired
        }
        throw ProviderErrorState.authNeeded
    }

    static func session(from rawValue: String, now: Date = Date()) throws -> CursorSession {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("WorkosCursorSessionToken=") {
            value.removeFirst("WorkosCursorSessionToken=".count)
        }
        value = value.replacingOccurrences(of: "%3A%3A", with: "::")

        let token: String
        let suppliedUserID: String?
        if let separator = value.range(of: "::") {
            suppliedUserID = String(value[..<separator.lowerBound])
            token = String(value[separator.upperBound...])
        } else {
            suppliedUserID = nil
            token = value
        }

        guard let claims = self.jwtClaims(token),
              claims["type"] as? String != "api_key_token"
        else {
            throw ProviderErrorState.authNeeded
        }
        if let expiration = self.doubleValue(claims["exp"]),
           Date(timeIntervalSince1970: expiration) <= now
        {
            throw ProviderErrorState.tokenExpired
        }

        let subject = suppliedUserID ?? self.cookieUserID(from: claims)
        guard let subject = self.trimmed(subject) else {
            throw ProviderErrorState.authNeeded
        }
        return CursorSession(cookieValue: "\(subject)%3A%3A\(token)")
    }

    private static func localAccessTokens() -> [String] {
        var tokens: [String] = []

        let home = FileManager.default.homeDirectoryForCurrentUser
        let applicationSupport = home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
        for appName in ["Cursor", "Cursor Nightly"] {
            let database = applicationSupport
                .appendingPathComponent(appName)
                .appendingPathComponent("User")
                .appendingPathComponent("globalStorage")
                .appendingPathComponent("state.vscdb")
            if let token = self.readAccessToken(fromDatabase: database) {
                tokens.append(token)
            }
        }

        for authFile in [
            home.appendingPathComponent(".config").appendingPathComponent("cursor").appendingPathComponent("auth.json"),
            home.appendingPathComponent(".cursor").appendingPathComponent("auth.json"),
        ] {
            if let token = self.readAccessToken(fromAuthFile: authFile) {
                tokens.append(token)
            }
        }
        return tokens
    }

    private static func readAccessToken(fromDatabase url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            if database != nil {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let query = "SELECT value FROM ItemTable WHERE key = '\(self.accessTokenKey)' LIMIT 1"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_text(statement, 0)
        else {
            return nil
        }
        return self.normalizedStoredToken(String(cString: bytes))
    }

    private static func readAccessToken(fromAuthFile url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return self.normalizedStoredToken(root["accessToken"] as? String)
    }

    private static func normalizedStoredToken(_ rawValue: String?) -> String? {
        guard let rawValue = self.trimmed(rawValue) else { return nil }
        if let data = rawValue.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(String.self, from: data)
        {
            return self.trimmed(decoded)
        }
        return rawValue
    }

    private static func jwtClaims(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return claims
    }

    private static func cookieUserID(from claims: [String: Any]) -> String? {
        guard let subject = claims["sub"] as? String else { return nil }
        return subject.split(separator: "|", omittingEmptySubsequences: false).last.map(String.init)
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

final class CursorDashboardTransport: CursorUsageTransport, @unchecked Sendable {
    static let shared = CursorDashboardTransport()
    static let currentPeriodURL = URL(
        string: "https://cursor.com/api/dashboard/get-current-period-usage"
    )!
    static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!

    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsagePayload(now: Date) async throws -> Data {
        let cursorSession = try CursorSessionReader.loadSession(now: now)
        let currentPeriodRequest = Self.makeCurrentPeriodRequest(session: cursorSession)

        do {
            let data = try await self.perform(currentPeriodRequest)
            if Self.isCurrentPeriodPayload(data) {
                return data
            }
        } catch let error as ProviderErrorState {
            switch error {
            case .authNeeded, .tokenExpired, .rateLimited:
                throw error
            default:
                break
            }
        }

        return try await self.perform(Self.makeUsageSummaryRequest(session: cursorSession))
    }

    static func makeCurrentPeriodRequest(session: CursorSession) -> URLRequest {
        var request = self.baseRequest(url: self.currentPeriodURL, session: session)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.httpBody = Data("{}".utf8)
        return request
    }

    static func makeUsageSummaryRequest(session: CursorSession) -> URLRequest {
        var request = self.baseRequest(url: self.usageSummaryURL, session: session)
        request.httpMethod = "GET"
        return request
    }

    static func errorState(for response: HTTPURLResponse) -> ProviderErrorState? {
        switch response.statusCode {
        case 200 ... 299:
            return nil
        case 401, 403:
            return .tokenExpired
        case 429:
            return .rateLimited(
                "Cursor dashboard request rate limited",
                retryAfter: response.retryAfterTimeInterval
            )
        default:
            return .endpointError("Cursor dashboard HTTP \(response.statusCode)")
        }
    }

    private static func baseRequest(url: URL, session: CursorSession) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "WorkosCursorSessionToken=\(session.cookieValue)",
            forHTTPHeaderField: "Cookie"
        )
        request.setValue("AIUsageMonitor", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func isCurrentPeriodPayload(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return root["planUsage"] is [String: Any]
            || root["billingCycleEnd"] != nil
            || root["isUnlimited"] != nil
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderErrorState.endpointError("Invalid Cursor dashboard response")
        }
        if let error = Self.errorState(for: http) {
            throw error
        }
        return data
    }
}
