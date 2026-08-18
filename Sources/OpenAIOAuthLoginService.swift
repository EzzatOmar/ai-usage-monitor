import AppKit
import Foundation

enum OpenAIOAuthLoginError: LocalizedError, Equatable {
    case loginAlreadyInProgress
    case callbackPortUnavailable
    case browserCouldNotOpen
    case cancelled
    case timedOut
    case invalidCallback
    case stateMismatch
    case authorizationRejected(String)
    case tokenExchangeFailed(Int)
    case invalidTokenResponse

    var errorDescription: String? {
        switch self {
        case .loginAlreadyInProgress:
            return "Another OpenAI login is already in progress."
        case .callbackPortUnavailable:
            return "OpenAI login could not start because callback ports 1455 and 1457 are unavailable."
        case .browserCouldNotOpen:
            return "The OpenAI login page could not be opened."
        case .cancelled:
            return "OpenAI login was cancelled."
        case .timedOut:
            return "OpenAI login timed out. Try again."
        case .invalidCallback:
            return "OpenAI returned an invalid login callback."
        case .stateMismatch:
            return "OpenAI login verification failed. Try again."
        case .authorizationRejected(let message):
            return message.isEmpty ? "OpenAI login was not authorized." : message
        case .tokenExchangeFailed(let status):
            return "OpenAI login could not exchange credentials (HTTP \(status))."
        case .invalidTokenResponse:
            return "OpenAI returned incomplete login credentials."
        }
    }
}

protocol OpenAIAccountAuthenticating: Sendable {
    func login(account: OpenAIAccountProfile) async throws
    func cancel(accountID: String) async
}

actor OpenAIOAuthLoginService: OpenAIAccountAuthenticating {
    static let shared = OpenAIOAuthLoginService()

    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let issuer = "https://auth.openai.com"
    private var activeLogin: (accountID: String, server: OpenAILocalCallbackServer)?

    func login(account: OpenAIAccountProfile) async throws {
        guard self.activeLogin == nil else {
            throw OpenAIOAuthLoginError.loginAlreadyInProgress
        }

        let server = try await self.startCallbackServer()
        self.activeLogin = (account.id, server)
        defer {
            server.cancel()
            self.activeLogin = nil
        }

        let pkce = try OpenAIPKCE.generate()
        let state = try OpenAIPKCE.randomURLSafeString(byteCount: 32)
        let redirectURI = "http://localhost:\(server.port)/auth/callback"
        let authorizationURL = try Self.authorizationURL(
            redirectURI: redirectURI,
            state: state,
            challenge: pkce.challenge
        )

        let opened = await MainActor.run {
            NSWorkspace.shared.open(authorizationURL)
        }
        guard opened else { throw OpenAIOAuthLoginError.browserCouldNotOpen }

        let callback: OpenAIOAuthCallback
        do {
            callback = try await Self.withTimeout(seconds: 5 * 60) {
                try await server.waitForCallback()
            }
        } catch is CancellationError {
            throw OpenAIOAuthLoginError.cancelled
        }

        guard callback.state == state else {
            server.respond(to: callback, success: false, message: "Login verification failed. Return to AI Usage Monitor and try again.")
            throw OpenAIOAuthLoginError.stateMismatch
        }
        if let error = callback.error {
            let message = callback.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            server.respond(to: callback, success: false, message: "Login was not authorized. Return to AI Usage Monitor and try again.")
            throw OpenAIOAuthLoginError.authorizationRejected(message.isEmpty ? error : message)
        }
        guard let code = callback.code, !code.isEmpty else {
            server.respond(to: callback, success: false, message: "Login response was incomplete. Return to AI Usage Monitor and try again.")
            throw OpenAIOAuthLoginError.invalidCallback
        }

        do {
            let tokens = try await Self.exchangeCode(
                code,
                redirectURI: redirectURI,
                verifier: pkce.verifier
            )
            guard tokens.idToken != nil, tokens.refreshToken != nil else {
                throw OpenAIOAuthLoginError.invalidTokenResponse
            }
            try Task.checkCancellation()
            let accountID = OpenAIAuthFileStore.extractAccountID(fromJWT: tokens.idToken)
                ?? OpenAIAuthFileStore.extractAccountID(fromJWT: tokens.accessToken)
            try OpenAIAuthFileStore.saveOAuthTokens(
                tokens,
                accountID: accountID,
                at: account.authURL()
            )
            server.respond(to: callback, success: true, message: "OpenAI account connected. You can close this page and return to AI Usage Monitor.")
        } catch {
            server.respond(to: callback, success: false, message: "Credentials could not be saved. Return to AI Usage Monitor and try again.")
            throw error
        }
    }

    func cancel(accountID: String) {
        guard self.activeLogin?.accountID == accountID else { return }
        self.activeLogin?.server.cancel()
    }

    static func authorizationURL(
        redirectURI: String,
        state: String,
        challenge: String
    ) throws -> URL {
        var components = URLComponents(string: self.issuer + "/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: self.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access api.connectors.read api.connectors.invoke"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "originator", value: "codex_cli_rs"),
        ]
        guard let url = components?.url else {
            throw OpenAIOAuthLoginError.invalidCallback
        }
        return url
    }

    private func startCallbackServer() async throws -> OpenAILocalCallbackServer {
        for port in [UInt16(1455), UInt16(1457)] {
            do {
                let server = try OpenAILocalCallbackServer(port: port)
                try await server.start()
                return server
            } catch {
                continue
            }
        }
        throw OpenAIOAuthLoginError.callbackPortUnavailable
    }

    private static func exchangeCode(
        _ code: String,
        redirectURI: String,
        verifier: String
    ) async throws -> OpenAITokenResponse {
        let url = URL(string: self.issuer + "/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("AIUsageMonitor", forHTTPHeaderField: "User-Agent")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "client_id", value: self.clientID),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIOAuthLoginError.invalidTokenResponse
        }
        guard http.statusCode == 200 else {
            throw OpenAIOAuthLoginError.tokenExchangeFailed(http.statusCode)
        }
        guard let tokens = try? JSONDecoder().decode(OpenAITokenResponse.self, from: data),
              !tokens.accessToken.isEmpty
        else {
            throw OpenAIOAuthLoginError.invalidTokenResponse
        }
        return tokens
    }

    private static func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw OpenAIOAuthLoginError.timedOut
            }
            guard let result = try await group.next() else {
                throw OpenAIOAuthLoginError.cancelled
            }
            group.cancelAll()
            return result
        }
    }
}
