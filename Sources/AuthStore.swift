import Foundation
import Security

enum AuthStore {
    private static let defaults = UserDefaults.standard
    private static let zaiKeyName = "aiUsageMonitor.zaiApiKey"
    private static let claudeTokenName = "aiUsageMonitor.claudeSetupToken"
    private static let claudeKeychainEnabledName = "aiUsageMonitor.claudeUseKeychain"

    static func loadZAIAPIKey() -> String? {
        let value = self.defaults.string(forKey: self.zaiKeyName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func saveZAIAPIKey(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.defaults.set(trimmed, forKey: self.zaiKeyName)
        return true
    }

    static func clearZAIAPIKey() {
        self.defaults.removeObject(forKey: self.zaiKeyName)
    }

    static func loadClaudeSetupToken() -> String? {
        let value = self.defaults.string(forKey: self.claudeTokenName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    static func saveClaudeSetupToken(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.defaults.set(trimmed, forKey: self.claudeTokenName)
        return true
    }

    static func clearClaudeSetupToken() {
        self.defaults.removeObject(forKey: self.claudeTokenName)
    }

    static func isClaudeKeychainEnabled() -> Bool {
        self.defaults.bool(forKey: self.claudeKeychainEnabledName)
    }

    static func setClaudeKeychainEnabled(_ enabled: Bool) {
        self.defaults.set(enabled, forKey: self.claudeKeychainEnabledName)
    }

    static func readClaudeTokenFromKeychainIfEnabled() -> String? {
        guard self.isClaudeKeychainEnabled() else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let nested = object["claudeAiOauth"] as? [String: Any],
           let token = nested["accessToken"] as? String,
           !token.isEmpty
        {
            return token
        }
        if let token = object["accessToken"] as? String, !token.isEmpty {
            return token
        }
        return nil
    }
}
