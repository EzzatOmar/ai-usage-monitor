import Foundation

struct ClaudeCLIRefreshPolicy {
    let cooldown: TimeInterval
    private(set) var lastLaunchAt: Date?

    mutating func markLaunch(at date: Date) {
        self.lastLaunchAt = date
    }

    func canLaunch(now: Date) -> Bool {
        guard let lastLaunchAt else { return true }
        return now.timeIntervalSince(lastLaunchAt) >= self.cooldown
    }
}

actor ClaudeCLISessionManager {
    static let shared = ClaudeCLISessionManager()

    private static let cooldownSeconds: TimeInterval = 600
    private static let autoCloseDelay: UInt64 = 15_000_000_000
    private static let secondCloseDelay: UInt64 = 2_000_000_000

    private var policy: ClaudeCLIRefreshPolicy
    private var trackedTTY: String?
    private var trackedWindowID: String?
    private var closeTask: Task<Void, Never>?

    private init() {
        self.policy = ClaudeCLIRefreshPolicy(cooldown: Self.cooldownSeconds, lastLaunchAt: nil)
    }

    func triggerRefreshIfNeeded() async {
        let now = Date()

        if let tty = self.trackedTTY {
            if self.isSessionOpen(tty: tty) {
                return
            }
            self.clearTrackedSessionReference()
        }

        guard self.policy.canLaunch(now: now) else { return }
        guard self.isClaudeInstalled() else { return }

        guard let session = self.launchClaudeSession() else { return }
        self.trackedTTY = session.tty
        self.trackedWindowID = session.windowID
        self.policy.markLaunch(at: now)

        self.closeTask?.cancel()
        self.closeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autoCloseDelay)
            await self?.closeTrackedSessionWithDoubleCheck()
        }
    }

    private func closeTrackedSessionWithDoubleCheck() async {
        guard let tty = self.trackedTTY else { return }

        _ = self.closeSession(tty: tty)
        if !self.isSessionOpen(tty: tty) {
            self.clearTrackedSessionReference()
            return
        }

        try? await Task.sleep(nanoseconds: Self.secondCloseDelay)

        _ = self.closeSession(tty: tty)
        if !self.isSessionOpen(tty: tty) {
            self.clearTrackedSessionReference()
        }
    }

    private func clearTrackedSessionReference() {
        self.trackedTTY = nil
        self.trackedWindowID = nil
    }

    private func isClaudeInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "claude"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func launchClaudeSession() -> (windowID: String, tty: String)? {
        let separator = "|"
        let result = self.runAppleScript([
            "tell application \"Terminal\"",
            "activate",
            "do script \"claude\"",
            "delay 0.2",
            "set targetWindow to front window",
            "set targetTab to selected tab of targetWindow",
            "return ((id of targetWindow) as string) & \"\(separator)\" & (tty of targetTab)",
            "end tell",
        ])

        guard let raw = result, !raw.isEmpty else { return nil }
        let parts = raw.split(separator: Character(separator), maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let windowID = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let tty = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !windowID.isEmpty, !tty.isEmpty else { return nil }
        return (windowID: windowID, tty: tty)
    }

    private func closeSession(tty: String) -> Bool {
        let escapedTTY = tty.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let result = self.runAppleScript([
            "tell application \"Terminal\"",
            "repeat with w in windows",
            "repeat with t in tabs of w",
            "if (tty of t) is \"\(escapedTTY)\" then",
            "do script \"exit\" in t",
            "delay 0.2",
            "if (count of tabs of w) > 1 then",
            "close t",
            "else",
            "close w",
            "end if",
            "return \"closed\"",
            "end if",
            "end repeat",
            "end repeat",
            "return \"not_found\"",
            "end tell",
        ])
        return result == "closed"
    }

    private func isSessionOpen(tty: String) -> Bool {
        let escapedTTY = tty.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let result = self.runAppleScript([
            "tell application \"Terminal\"",
            "repeat with w in windows",
            "repeat with t in tabs of w",
            "if (tty of t) is \"\(escapedTTY)\" then",
            "return \"open\"",
            "end if",
            "end repeat",
            "end repeat",
            "return \"closed\"",
            "end tell",
        ])
        return result == "open"
    }

    private func runAppleScript(_ lines: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")

        var args: [String] = []
        args.reserveCapacity(lines.count * 2)
        for line in lines {
            args.append("-e")
            args.append(line)
        }
        process.arguments = args

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
