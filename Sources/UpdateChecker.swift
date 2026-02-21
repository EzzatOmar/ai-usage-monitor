import AppKit
import Foundation

enum UpdateStatus: Sendable, Equatable {
    case unknown
    case upToDate
    case available(version: String, downloadURL: URL)
    case downloading
    case readyToInstall
    case error(String)
}

struct SemVer: Comparable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ string: String) {
        let cleaned = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = cleaned.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.major = parts[0]
        self.minor = parts[1]
        self.patch = parts[2]
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

actor UpdateChecker {
    static let shared = UpdateChecker()

    private static let repoAPI = "https://api.github.com/repos/EzzatOmar/ai-usage-monitor/releases/latest"
    private static let checkInterval: UInt64 = 4 * 60 * 60 // 4 hours in seconds

    private var status: UpdateStatus = .unknown
    private var continuations: [UUID: AsyncStream<UpdateStatus>.Continuation] = [:]
    private var pollTask: Task<Void, Never>?

    private init() {}

    private static var updateLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("AIUsageMonitor")
            .appendingPathComponent("update.log")
    }

    deinit {
        self.pollTask?.cancel()
    }

    var currentStatus: UpdateStatus {
        self.status
    }

    func statusUpdates() -> AsyncStream<UpdateStatus> {
        AsyncStream { continuation in
            let id = UUID()
            self.continuations[id] = continuation
            continuation.yield(self.status)
            continuation.onTermination = { [weak self] _ in
                let actor = self
                Task { await actor?.removeContinuation(id: id) }
            }
        }
    }

    func start() {
        guard self.pollTask == nil else { return }
        guard Self.isInstalledApp else { return }

        self.pollTask = Task {
            await self.checkForUpdate()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.checkInterval * 1_000_000_000)
                await self.checkForUpdate()
            }
        }
    }

    func checkForUpdate() async {
        guard Self.isInstalledApp else { return }
        guard let currentVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              let current = SemVer(currentVersionString) else {
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: URL(string: Self.repoAPI)!)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let remote = SemVer(tagName) else {
                return
            }

            guard remote > current else {
                self.status = .upToDate
                self.publish()
                return
            }

            guard let assets = json["assets"] as? [[String: Any]],
                  let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                  let downloadURLString = dmgAsset["browser_download_url"] as? String,
                  let downloadURL = URL(string: downloadURLString) else {
                return
            }

            self.status = .available(version: tagName, downloadURL: downloadURL)
            self.publish()
        } catch {
            // Silent failure for periodic checks
        }
    }

    func triggerDownloadAndInstall() async {
        guard case .available(_, let downloadURL) = self.status else { return }
        self.log("Starting update download from \(downloadURL.absoluteString)")
        guard let appPath = Self.currentAppPath else {
            self.status = .error("Cannot determine app location")
            self.log("Update failed: cannot determine app location")
            self.publish()
            return
        }

        self.status = .downloading
        self.publish()

        do {
            // 1. Download DMG
            let (tempDMGURL, response) = try await URLSession.shared.download(from: downloadURL)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                self.status = .error("Download failed")
                self.log("Update failed: DMG download returned non-200 status")
                self.publish()
                return
            }

            let dmgPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("AIUsageMonitor-update.dmg")
            try? FileManager.default.removeItem(at: dmgPath)
            try FileManager.default.moveItem(at: tempDMGURL, to: dmgPath)

            // 2. Mount DMG
            let mountProcess = Process()
            mountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            mountProcess.arguments = ["attach", dmgPath.path, "-nobrowse", "-plist"]
            let mountPipe = Pipe()
            mountProcess.standardOutput = mountPipe
            let mountErrorPipe = Pipe()
            mountProcess.standardError = mountErrorPipe
            try mountProcess.run()
            mountProcess.waitUntilExit()

            guard mountProcess.terminationStatus == 0 else {
                self.status = .error("Failed to mount update")
                let mountError = mountErrorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: mountError, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.log("Update failed: hdiutil attach returned \(mountProcess.terminationStatus). \(message)")
                self.publish()
                return
            }

            let mountData = mountPipe.fileHandleForReading.readDataToEndOfFile()
            guard let mountPlist = try PropertyListSerialization.propertyList(
                from: mountData, format: nil
            ) as? [String: Any],
                  let entities = mountPlist["system-entities"] as? [[String: Any]],
                  let mountPoint = entities.first(where: { $0["mount-point"] != nil })?["mount-point"] as? String else {
                self.status = .error("Failed to locate mounted volume")
                self.log("Update failed: unable to parse mount plist")
                self.publish()
                return
            }

            self.log("Mounted update DMG at \(mountPoint)")

            // 3. Find .app in mounted volume
            let volumeURL = URL(fileURLWithPath: mountPoint)
            let contents = try FileManager.default.contentsOfDirectory(
                at: volumeURL, includingPropertiesForKeys: nil
            )
            guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
                self.unmountDMG(mountPoint: mountPoint)
                self.status = .error("No app found in update")
                self.log("Update failed: no .app bundle found in mounted DMG")
                self.publish()
                return
            }

            // 4. Copy to staging
            let stagingPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("AIUsageMonitor-staged.app")
            try? FileManager.default.removeItem(at: stagingPath)
            try FileManager.default.copyItem(at: appBundle, to: stagingPath)

            // 5. Unmount
            self.unmountDMG(mountPoint: mountPoint)

            // 6. Clean up DMG
            try? FileManager.default.removeItem(at: dmgPath)

            // 7. Launch helper and quit
            guard let helperURL = Bundle.main.url(forResource: "update_helper", withExtension: "sh") else {
                self.status = .error("Update helper not found")
                self.log("Update failed: helper script missing in app bundle")
                self.publish()
                return
            }

            self.status = .readyToInstall
            self.publish()

            let pid = ProcessInfo.processInfo.processIdentifier
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/bin/bash")
            helper.arguments = [
                helperURL.path,
                String(pid),
                stagingPath.path,
                appPath,
            ]
            helper.standardOutput = nil
            helper.standardError = nil
            // Detach so the helper survives our exit
            helper.qualityOfService = .utility
            try helper.run()
            self.log("Update helper launched; app will terminate for install")

            // Quit the app
            await MainActor.run {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            self.status = .error("Update failed: \(error.localizedDescription)")
            self.log("Update failed with error: \(error.localizedDescription)")
            self.publish()
        }
    }

    // MARK: - Private

    private static var isInstalledApp: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    private static var currentAppPath: String? {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { return nil }
        return path
    }

    private func unmountDMG(mountPoint: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", mountPoint, "-quiet"]
        try? process.run()
        process.waitUntilExit()
    }

    private func removeContinuation(id: UUID) {
        self.continuations.removeValue(forKey: id)
    }

    private func publish() {
        for continuation in self.continuations.values {
            continuation.yield(self.status)
        }
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        let url = Self.updateLogURL
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
