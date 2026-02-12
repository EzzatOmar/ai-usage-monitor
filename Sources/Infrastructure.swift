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

enum CommandRunner {
    enum CommandError: Error {
        case launchFailed
        case timedOut
        case nonZeroExit(Int32, String)
    }

    static func run(_ launchPath: String, arguments: [String], timeout: TimeInterval = 8) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw CommandError.timedOut
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw CommandError.nonZeroExit(process.terminationStatus, text)
        }
        return text
    }
}
