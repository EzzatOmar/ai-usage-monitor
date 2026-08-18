import Darwin
import Foundation

struct OpenAIOAuthCredentials: Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let idToken: String?
    let accountID: String?
    let lastRefresh: Date?
    let expiresAt: Date?

    var needsRefresh: Bool {
        if let expiresAt {
            return Date().addingTimeInterval(5 * 60) >= expiresAt
        }
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > (8 * 24 * 60 * 60)
    }
}

enum OpenAIStoredCredential: Sendable, Equatable {
    case oauth(OpenAIOAuthCredentials)
    case apiKey(String)
}

struct OpenAITokenResponse: Decodable, Sendable, Equatable {
    let idToken: String?
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum OpenAIAuthFileStore {
    static func loadCredential(at url: URL) throws -> OpenAIStoredCredential? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let root = try JSONFile.readDictionary(at: url)

        if let oauth = self.oauthCredentials(from: root) {
            return .oauth(oauth)
        }
        if let apiKey = self.trimmedNonempty(root["OPENAI_API_KEY"] as? String) {
            return .apiKey(apiKey)
        }
        return nil
    }

    static func hasCredential(at url: URL) -> Bool {
        (try? self.loadCredential(at: url)) != nil
    }

    static func saveOAuthTokens(
        _ response: OpenAITokenResponse,
        accountID: String?,
        at url: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws {
        guard let refreshToken = self.trimmedNonempty(response.refreshToken),
              let idToken = self.trimmedNonempty(response.idToken)
        else {
            throw ProviderErrorState.parseError("OpenAI login response did not include OAuth credentials")
        }
        let resolvedAccountID = self.trimmedNonempty(accountID)
            ?? self.extractAccountID(fromJWT: idToken)
            ?? self.extractAccountID(fromJWT: response.accessToken)
        let tokens: [String: Any] = [
            "id_token": idToken,
            "access_token": response.accessToken,
            "refresh_token": refreshToken,
            "account_id": resolvedAccountID ?? NSNull(),
        ]
        let root: [String: Any] = [
            "auth_mode": "chatgpt",
            "OPENAI_API_KEY": NSNull(),
            "tokens": tokens,
            "last_refresh": self.iso8601String(now),
        ]
        try self.writeRoot(root, to: url, fileManager: fileManager)
    }

    static func persistRefreshedOAuth(
        _ response: OpenAITokenResponse,
        replacing credentials: OpenAIOAuthCredentials,
        at url: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> OpenAIOAuthCredentials {
        var root = try JSONFile.readDictionary(at: url)
        if let latest = self.oauthCredentials(from: root),
           latest.refreshToken != credentials.refreshToken {
            return latest
        }

        guard var tokens = root["tokens"] as? [String: Any] else {
            throw ProviderErrorState.parseError("OpenAI auth file is missing OAuth tokens")
        }
        let refreshToken = self.trimmedNonempty(response.refreshToken) ?? credentials.refreshToken
        let idToken = self.trimmedNonempty(response.idToken) ?? credentials.idToken
        let refreshedAccountID = self.extractAccountID(fromJWT: response.idToken)
            ?? self.extractAccountID(fromJWT: response.accessToken)
        if let existingAccountID = credentials.accountID,
           let refreshedAccountID,
           existingAccountID != refreshedAccountID {
            throw ProviderErrorState.tokenExpired
        }
        let accountID = refreshedAccountID ?? credentials.accountID

        tokens["access_token"] = response.accessToken
        tokens["refresh_token"] = refreshToken
        if let idToken {
            tokens["id_token"] = idToken
        }
        if let accountID {
            tokens["account_id"] = accountID
        }
        root["auth_mode"] = "chatgpt"
        root["tokens"] = tokens
        root["last_refresh"] = self.iso8601String(now)
        try self.writeRoot(root, to: url, fileManager: fileManager)

        guard case .oauth(let updated)? = try self.loadCredential(at: url) else {
            throw ProviderErrorState.parseError("Refreshed OpenAI credentials could not be reloaded")
        }
        return updated
    }

    static func removeCredential(at url: URL, fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    static func extractAccountID(fromJWT token: String?) -> String? {
        guard let claims = self.jwtClaims(token) else { return nil }
        if let accountID = self.trimmedNonempty(claims["chatgpt_account_id"] as? String) {
            return accountID
        }
        if let auth = claims["https://api.openai.com/auth"] as? [String: Any],
           let accountID = self.trimmedNonempty(auth["chatgpt_account_id"] as? String) {
            return accountID
        }
        if let organizations = claims["organizations"] as? [[String: Any]] {
            return organizations.compactMap { self.trimmedNonempty($0["id"] as? String) }.first
        }
        return nil
    }

    static func extractExpiration(fromJWT token: String?) -> Date? {
        guard let claims = self.jwtClaims(token) else { return nil }
        if let seconds = claims["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: seconds)
        }
        if let number = claims["exp"] as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        return nil
    }

    static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    private static func oauthCredentials(from root: [String: Any]) -> OpenAIOAuthCredentials? {
        guard let tokens = root["tokens"] as? [String: Any],
              let accessToken = self.trimmedNonempty(tokens["access_token"] as? String),
              let refreshToken = self.trimmedNonempty(tokens["refresh_token"] as? String)
        else {
            return nil
        }
        let idToken = self.trimmedNonempty(tokens["id_token"] as? String)
        let accountID = self.trimmedNonempty(tokens["account_id"] as? String)
            ?? self.extractAccountID(fromJWT: idToken)
            ?? self.extractAccountID(fromJWT: accessToken)
        return OpenAIOAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            accountID: accountID,
            lastRefresh: self.parseISO8601(root["last_refresh"] as? String),
            expiresAt: self.extractExpiration(fromJWT: accessToken)
        )
    }

    private static func writeRoot(
        _ root: [String: Any],
        to url: URL,
        fileManager: FileManager
    ) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard chmod(directory.path, 0o700) == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        guard chmod(url.path, 0o600) == 0 else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func jwtClaims(_ token: String?) -> [String: Any]? {
        guard let token, !token.isEmpty else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let data = Data(base64URLEncoded: String(parts[1])),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return claims
    }

    private static func trimmedNonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
