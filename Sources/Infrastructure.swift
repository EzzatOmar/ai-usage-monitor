import Foundation

enum Redaction {
    static func sanitize(_ text: String) -> String {
        let tokenPattern = #"(?i)(bearer\s+)[a-z0-9\-\._~\+\/]+=*"#
        guard let regex = try? NSRegularExpression(pattern: tokenPattern) else { return text }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1<redacted>")
    }
}

enum LocalPaths {
    static func codexHomeURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let home = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    static func codexAuthPath(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        self.codexHomeURL(env: env).appendingPathComponent("auth.json")
    }

    static func codexConfigPath(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        self.codexHomeURL(env: env).appendingPathComponent("config.toml")
    }

    static func claudeCredentialsPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent(".credentials.json")
    }

    static func geminiSettingsPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini")
            .appendingPathComponent("settings.json")
    }

    static func geminiOAuthPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini")
            .appendingPathComponent("oauth_creds.json")
    }

}

enum JSONFile {
    static func readDictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        return object
    }
}

extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension HTTPURLResponse {
    var retryAfterTimeInterval: TimeInterval? {
        for (key, value) in self.allHeaderFields {
            guard let headerName = key as? String, headerName.lowercased() == "retry-after" else { continue }
            if let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let seconds = TimeInterval(trimmed) {
                    return max(0, seconds)
                }
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss zzz"
                if let date = formatter.date(from: trimmed) {
                    return max(0, date.timeIntervalSinceNow)
                }
            }
        }
        return nil
    }
}
