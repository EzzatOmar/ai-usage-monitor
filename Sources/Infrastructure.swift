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
    static func codexAuthPath(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let home = env["CODEX_HOME"], !home.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("auth.json")
    }

    static func codexConfigPath(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let home = env["CODEX_HOME"], !home.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: home).appendingPathComponent("config.toml")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("config.toml")
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

    static func opencodeAuthPaths(env: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths: [URL] = []

        if let xdgDataHome = env["XDG_DATA_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines), !xdgDataHome.isEmpty {
            paths.append(URL(fileURLWithPath: xdgDataHome).appendingPathComponent("opencode").appendingPathComponent("auth.json"))
        }

        paths.append(home.appendingPathComponent("Library").appendingPathComponent("Application Support").appendingPathComponent("opencode").appendingPathComponent("auth.json"))
        paths.append(home.appendingPathComponent(".local").appendingPathComponent("share").appendingPathComponent("opencode").appendingPathComponent("auth.json"))
        return paths
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
