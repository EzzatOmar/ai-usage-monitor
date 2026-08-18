import Foundation

enum OpenAIAccountStorage: String, Codable, Sendable {
    case defaultCodex
    case managed
}

struct OpenAIAccountProfile: Codable, Hashable, Identifiable, Sendable {
    static let defaultID = "openai-default"

    let id: String
    var name: String
    var isEnabled: Bool
    let storage: OpenAIAccountStorage

    static func defaultAccount(name: String = "OpenAI", isEnabled: Bool = true) -> Self {
        Self(
            id: Self.defaultID,
            name: name,
            isEnabled: isEnabled,
            storage: .defaultCodex
        )
    }

    var isDefault: Bool {
        self.storage == .defaultCodex
    }

    func codexHomeURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        switch self.storage {
        case .defaultCodex:
            return LocalPaths.codexHomeURL(env: env, fileManager: fileManager)
        case .managed:
            return OpenAIAccountStore.managedAccountsRoot(fileManager: fileManager)
                .appendingPathComponent(self.id, isDirectory: true)
        }
    }

    func authURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        self.codexHomeURL(env: env, fileManager: fileManager)
            .appendingPathComponent("auth.json")
    }

    func configURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        self.codexHomeURL(env: env, fileManager: fileManager)
            .appendingPathComponent("config.toml")
    }
}

enum OpenAIAccountStoreError: LocalizedError, Equatable {
    case emptyName
    case duplicateName
    case cannotRemoveDefault
    case invalidManagedAccount

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Enter an account name."
        case .duplicateName:
            return "Use a unique account name."
        case .cannotRemoveDefault:
            return "The default OpenAI account cannot be removed."
        case .invalidManagedAccount:
            return "The managed OpenAI account is invalid."
        }
    }
}

enum OpenAIAccountStore {
    private static let accountsKey = "aiUsageMonitor.openAIAccounts.v1"

    static func loadAccounts(
        defaults: UserDefaults = .standard,
        defaultEnabled: Bool? = nil
    ) -> [OpenAIAccountProfile] {
        let fallbackEnabled = defaultEnabled ?? AuthStore.isProviderEnabled(.codex)
        guard let data = defaults.data(forKey: self.accountsKey),
              let decoded = try? JSONDecoder().decode([OpenAIAccountProfile].self, from: data)
        else {
            return [.defaultAccount(isEnabled: fallbackEnabled)]
        }

        var defaultAccount = decoded.first(where: { $0.storage == .defaultCodex })
            ?? .defaultAccount(isEnabled: fallbackEnabled)
        defaultAccount = OpenAIAccountProfile(
            id: OpenAIAccountProfile.defaultID,
            name: self.normalizedStoredName(defaultAccount.name, fallback: "OpenAI"),
            isEnabled: defaultAccount.isEnabled,
            storage: .defaultCodex
        )

        var seenIDs = Set<String>()
        var seenNames = Set([defaultAccount.name.lowercased()])
        let managed = decoded.compactMap { account -> OpenAIAccountProfile? in
            guard account.storage == .managed,
                  let uuid = UUID(uuidString: account.id)
            else {
                return nil
            }
            let canonicalID = uuid.uuidString.lowercased()
            guard seenIDs.insert(canonicalID).inserted else { return nil }
            let name = self.normalizedStoredName(account.name, fallback: "OpenAI account")
            guard seenNames.insert(name.lowercased()).inserted else { return nil }
            return OpenAIAccountProfile(
                id: canonicalID,
                name: name,
                isEnabled: account.isEnabled,
                storage: .managed
            )
        }
        return [defaultAccount] + managed
    }

    static func saveAccounts(
        _ accounts: [OpenAIAccountProfile],
        defaults: UserDefaults = .standard
    ) throws {
        let normalized = try self.validatedAccounts(accounts)
        defaults.set(try JSONEncoder().encode(normalized), forKey: self.accountsKey)
    }

    static func addingAccount(
        named rawName: String,
        to accounts: [OpenAIAccountProfile],
        id: UUID = UUID()
    ) throws -> [OpenAIAccountProfile] {
        let name = try self.validatedName(rawName, excludingAccountID: nil, accounts: accounts)
        var updated = accounts
        updated.append(OpenAIAccountProfile(
            id: id.uuidString.lowercased(),
            name: name,
            isEnabled: true,
            storage: .managed
        ))
        return try self.validatedAccounts(updated)
    }

    static func renamingAccount(
        id: String,
        to rawName: String,
        in accounts: [OpenAIAccountProfile]
    ) throws -> [OpenAIAccountProfile] {
        let name = try self.validatedName(rawName, excludingAccountID: id, accounts: accounts)
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            throw OpenAIAccountStoreError.invalidManagedAccount
        }
        var updated = accounts
        updated[index].name = name
        return try self.validatedAccounts(updated)
    }

    static func settingAccountEnabled(
        id: String,
        enabled: Bool,
        in accounts: [OpenAIAccountProfile]
    ) throws -> [OpenAIAccountProfile] {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            throw OpenAIAccountStoreError.invalidManagedAccount
        }
        var updated = accounts
        updated[index].isEnabled = enabled
        return try self.validatedAccounts(updated)
    }

    static func removingAccount(
        id: String,
        from accounts: [OpenAIAccountProfile]
    ) throws -> [OpenAIAccountProfile] {
        guard id != OpenAIAccountProfile.defaultID else {
            throw OpenAIAccountStoreError.cannotRemoveDefault
        }
        guard let account = accounts.first(where: { $0.id == id }), account.storage == .managed else {
            throw OpenAIAccountStoreError.invalidManagedAccount
        }
        return accounts.filter { $0.id != id }
    }

    static func deleteManagedAuth(
        for account: OpenAIAccountProfile,
        fileManager: FileManager = .default
    ) throws {
        guard account.storage == .managed, UUID(uuidString: account.id) != nil else {
            throw OpenAIAccountStoreError.invalidManagedAccount
        }
        let directory = account.codexHomeURL(fileManager: fileManager)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    static func managedAccountsRoot(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("AIUsageMonitor", isDirectory: true)
            .appendingPathComponent("OpenAIAccounts", isDirectory: true)
    }

    private static func validatedAccounts(
        _ accounts: [OpenAIAccountProfile]
    ) throws -> [OpenAIAccountProfile] {
        guard let existingDefault = accounts.first(where: { $0.storage == .defaultCodex }) else {
            throw OpenAIAccountStoreError.invalidManagedAccount
        }
        let defaultName = try self.validatedName(
            existingDefault.name,
            excludingAccountID: existingDefault.id,
            accounts: accounts
        )
        let defaultAccount = OpenAIAccountProfile.defaultAccount(
            name: defaultName,
            isEnabled: existingDefault.isEnabled
        )
        var result = [defaultAccount]
        var seenIDs = Set<String>()
        var seenNames = Set([defaultName.lowercased()])

        for account in accounts where account.storage == .managed {
            guard let uuid = UUID(uuidString: account.id) else {
                throw OpenAIAccountStoreError.invalidManagedAccount
            }
            let canonicalID = uuid.uuidString.lowercased()
            guard seenIDs.insert(canonicalID).inserted else {
                throw OpenAIAccountStoreError.invalidManagedAccount
            }
            let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw OpenAIAccountStoreError.emptyName }
            guard seenNames.insert(name.lowercased()).inserted else {
                throw OpenAIAccountStoreError.duplicateName
            }
            result.append(OpenAIAccountProfile(
                id: canonicalID,
                name: name,
                isEnabled: account.isEnabled,
                storage: .managed
            ))
        }
        return result
    }

    private static func validatedName(
        _ rawName: String,
        excludingAccountID: String?,
        accounts: [OpenAIAccountProfile]
    ) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw OpenAIAccountStoreError.emptyName }
        let duplicate = accounts.contains {
            $0.id != excludingAccountID
                && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard !duplicate else { throw OpenAIAccountStoreError.duplicateName }
        return String(name.prefix(80))
    }

    private static func normalizedStoredName(_ raw: String, fallback: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallback : String(name.prefix(80))
    }
}
