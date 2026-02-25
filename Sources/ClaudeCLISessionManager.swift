import Foundation
import Darwin

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
    private static let autoStopDelay: UInt64 = 15_000_000_000
    private static let secondStopCheckDelay: UInt64 = 2_000_000_000

    private var policy: ClaudeCLIRefreshPolicy
    private var activeProcess: Process?
    private var activeSessionID: UUID?
    private var stopTask: Task<Void, Never>?

    private init() {
        self.policy = ClaudeCLIRefreshPolicy(cooldown: Self.cooldownSeconds, lastLaunchAt: nil)
    }

    func triggerRefreshIfNeeded() async {
        if let process = self.activeProcess {
            if process.isRunning {
                return
            }
            self.clearActiveProcess()
        }

        let now = Date()
        guard self.policy.canLaunch(now: now) else { return }
        guard self.isClaudeInstalled() else { return }

        await self.stopActiveProcessIfNeeded()

        guard let process = self.launchClaudeInBackground() else { return }

        let sessionID = UUID()
        self.activeSessionID = sessionID
        self.activeProcess = process
        self.policy.markLaunch(at: now)

        self.stopTask?.cancel()
        self.stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autoStopDelay)
            await self?.stopSessionIfNeeded(sessionID: sessionID)
        }
    }

    private func stopActiveProcessIfNeeded() async {
        guard let process = self.activeProcess else { return }
        await self.stopProcessWithDoubleCheck(process)
        self.clearActiveProcess()
    }

    private func stopSessionIfNeeded(sessionID: UUID) async {
        guard sessionID == self.activeSessionID, let process = self.activeProcess else { return }
        await self.stopProcessWithDoubleCheck(process)
        if sessionID == self.activeSessionID {
            self.clearActiveProcess()
        }
    }

    private func stopProcessWithDoubleCheck(_ process: Process) async {
        guard process.isRunning else { return }

        process.terminate()
        if !process.isRunning { return }

        try? await Task.sleep(nanoseconds: Self.secondStopCheckDelay)
        if process.isRunning {
            _ = kill(process.processIdentifier, SIGKILL)
        }
    }

    private func clearActiveProcess() {
        self.activeProcess = nil
        self.activeSessionID = nil
    }

    private func isClaudeInstalled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "claude"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func launchClaudeInBackground() -> Process? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "claude",
            "--print",
            "refresh",
            "--output-format",
            "text",
            "--no-session-persistence",
        ]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            return process
        } catch {
            return nil
        }
    }
}
