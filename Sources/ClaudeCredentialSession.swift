import Foundation

actor ClaudeCredentialSession {
    typealias KeychainReader = @Sendable (Bool) -> ClaudeKeychainCredentials?
    typealias KeychainEnabledReader = @Sendable () -> Bool

    static let shared = ClaudeCredentialSession(
        keychainReader: { allowInteraction in
            AuthStore.readClaudeKeychainCredentials(allowInteraction: allowInteraction)
        },
        keychainEnabledReader: {
            AuthStore.isClaudeKeychainEnabled()
        }
    )

    private let keychainReader: KeychainReader
    private let keychainEnabledReader: KeychainEnabledReader
    private var cachedCredentials: ClaudeKeychainCredentials?

    init(
        keychainReader: @escaping KeychainReader,
        keychainEnabledReader: @escaping KeychainEnabledReader = { true }
    ) {
        self.keychainReader = keychainReader
        self.keychainEnabledReader = keychainEnabledReader
    }

    func credentials(allowInteraction: Bool) -> ClaudeKeychainCredentials? {
        guard self.keychainEnabledReader() else {
            self.cachedCredentials = nil
            return nil
        }

        if let cachedCredentials {
            return cachedCredentials
        }

        guard let credentials = self.keychainReader(allowInteraction) else {
            return nil
        }
        self.cachedCredentials = credentials
        return credentials
    }

    func clear() {
        self.cachedCredentials = nil
    }
}
