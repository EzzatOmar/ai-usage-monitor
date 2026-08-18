import Network
import XCTest
@testable import AIUsageMonitor

final class OpenAIAccountTests: XCTestCase {
    func test_defaultAccountUsesDefaultCodexPathAndManagedAccountsUseAppFolder() throws {
        let defaultAccount = OpenAIAccountProfile.defaultAccount(name: "Personal")
        let managed = try XCTUnwrap(
            OpenAIAccountStore.addingAccount(
                named: "Work",
                to: [defaultAccount],
                id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
            ).last
        )

        XCTAssertEqual(
            defaultAccount.authURL(env: ["CODEX_HOME": "/tmp/custom-codex"]).path,
            "/tmp/custom-codex/auth.json"
        )
        XCTAssertEqual(managed.storage, .managed)
        XCTAssertTrue(managed.authURL().path.contains("AIUsageMonitor/OpenAIAccounts/"))
        XCTAssertTrue(managed.authURL().path.hasSuffix("/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/auth.json"))
    }

    func test_accountMetadataPersistsNamesAndEnabledState() throws {
        let suiteName = "OpenAIAccountTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var accounts = OpenAIAccountStore.loadAccounts(defaults: defaults, defaultEnabled: false)
        XCTAssertEqual(accounts, [.defaultAccount(isEnabled: false)])

        accounts = try OpenAIAccountStore.renamingAccount(
            id: OpenAIAccountProfile.defaultID,
            to: "Personal",
            in: accounts
        )
        accounts = try OpenAIAccountStore.addingAccount(
            named: " Work ",
            to: accounts,
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
        accounts = try OpenAIAccountStore.settingAccountEnabled(
            id: accounts[1].id,
            enabled: false,
            in: accounts
        )
        try OpenAIAccountStore.saveAccounts(accounts, defaults: defaults)

        XCTAssertEqual(OpenAIAccountStore.loadAccounts(defaults: defaults), accounts)
        XCTAssertEqual(accounts.map(\.name), ["Personal", "Work"])
        XCTAssertEqual(accounts.map(\.isEnabled), [false, false])
    }

    func test_accountNamesMustBeNonemptyAndUniqueAndDefaultCannotBeRemoved() throws {
        let accounts = [OpenAIAccountProfile.defaultAccount(name: "Personal")]

        XCTAssertThrowsError(try OpenAIAccountStore.addingAccount(named: "  ", to: accounts)) {
            XCTAssertEqual($0 as? OpenAIAccountStoreError, .emptyName)
        }
        XCTAssertThrowsError(try OpenAIAccountStore.addingAccount(named: "personal", to: accounts)) {
            XCTAssertEqual($0 as? OpenAIAccountStoreError, .duplicateName)
        }
        XCTAssertThrowsError(
            try OpenAIAccountStore.removingAccount(
                id: OpenAIAccountProfile.defaultID,
                from: accounts
            )
        ) {
            XCTAssertEqual($0 as? OpenAIAccountStoreError, .cannotRemoveDefault)
        }
    }

    func test_oauthCredentialsAreStoredWithRestrictedPermissionsAndRotatedAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenAIAuthFileTests-\(UUID().uuidString)", isDirectory: true)
        let authURL = directory.appendingPathComponent("auth.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountID = "acct_personal"
        let initialIDToken = self.jwt(["chatgpt_account_id": accountID])
        let initialAccess = self.jwt([
            "chatgpt_account_id": accountID,
            "exp": Date().addingTimeInterval(3_600).timeIntervalSince1970,
        ])
        try OpenAIAuthFileStore.saveOAuthTokens(
            OpenAITokenResponse(
                idToken: initialIDToken,
                accessToken: initialAccess,
                refreshToken: "refresh-initial",
                expiresIn: 3_600
            ),
            accountID: nil,
            at: authURL
        )

        let fileMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: authURL.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        let directoryMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        ).intValue & 0o777
        XCTAssertEqual(fileMode, 0o600)
        XCTAssertEqual(directoryMode, 0o700)

        guard case .oauth(let initial)? = try OpenAIAuthFileStore.loadCredential(at: authURL) else {
            return XCTFail("Expected OAuth credentials")
        }
        XCTAssertEqual(initial.accountID, accountID)
        XCTAssertEqual(initial.refreshToken, "refresh-initial")

        let refreshedAccess = self.jwt([
            "chatgpt_account_id": accountID,
            "exp": Date().addingTimeInterval(7_200).timeIntervalSince1970,
        ])
        let refreshed = try OpenAIAuthFileStore.persistRefreshedOAuth(
            OpenAITokenResponse(
                idToken: nil,
                accessToken: refreshedAccess,
                refreshToken: "refresh-rotated",
                expiresIn: 7_200
            ),
            replacing: initial,
            at: authURL
        )

        XCTAssertEqual(refreshed.accessToken, refreshedAccess)
        XCTAssertEqual(refreshed.refreshToken, "refresh-rotated")
        XCTAssertEqual(refreshed.idToken, initialIDToken)
        XCTAssertEqual(refreshed.accountID, accountID)
    }

    func test_permanentRefreshResponsesRequireLoginAgain() {
        for status in [400, 401, 403] {
            XCTAssertEqual(
                CodexClient.refreshFailure(statusCode: status, retryAfter: nil),
                .tokenExpired
            )
        }
        XCTAssertEqual(
            CodexClient.refreshFailure(statusCode: 429, retryAfter: 12),
            .rateLimited("OpenAI authentication is rate limited", retryAfter: 12)
        )
        XCTAssertEqual(
            CodexClient.refreshFailure(statusCode: 500, retryAfter: nil),
            .endpointError("OpenAI refresh failed (HTTP 500)")
        )
    }

    func test_refreshRejectsTokensForAnotherAccount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenAIAuthMismatchTests-\(UUID().uuidString)", isDirectory: true)
        let authURL = directory.appendingPathComponent("auth.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try OpenAIAuthFileStore.saveOAuthTokens(
            OpenAITokenResponse(
                idToken: self.jwt(["chatgpt_account_id": "acct_one"]),
                accessToken: self.jwt(["chatgpt_account_id": "acct_one"]),
                refreshToken: "refresh-one",
                expiresIn: nil
            ),
            accountID: nil,
            at: authURL
        )
        guard case .oauth(let initial)? = try OpenAIAuthFileStore.loadCredential(at: authURL) else {
            return XCTFail("Expected OAuth credentials")
        }

        XCTAssertThrowsError(
            try OpenAIAuthFileStore.persistRefreshedOAuth(
                OpenAITokenResponse(
                    idToken: self.jwt(["chatgpt_account_id": "acct_two"]),
                    accessToken: self.jwt(["chatgpt_account_id": "acct_two"]),
                    refreshToken: "refresh-two",
                    expiresIn: nil
                ),
                replacing: initial,
                at: authURL
            )
        ) {
            XCTAssertEqual($0 as? ProviderErrorState, .tokenExpired)
        }
    }

    func test_pkceAndAuthorizationURLContainRequiredOAuthParameters() throws {
        let codes = try OpenAIPKCE.generate()
        let url = try OpenAIOAuthLoginService.authorizationURL(
            redirectURI: "http://localhost:1455/auth/callback",
            state: "state-value",
            challenge: codes.challenge
        )
        let items = Dictionary(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map {
                ($0.name, $0.value ?? "")
            } ?? [],
            uniquingKeysWith: { first, _ in first }
        )

        XCTAssertNotEqual(codes.verifier, codes.challenge)
        XCTAssertEqual(items["client_id"], "app_EMoamEEZ73f0CkXaXp7hrann")
        XCTAssertEqual(items["redirect_uri"], "http://localhost:1455/auth/callback")
        XCTAssertEqual(items["state"], "state-value")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertTrue(items["scope"]?.contains("offline_access") == true)
    }

    @MainActor
    func test_viewModelStartsNamedAccountLoginAndReturnsToIdleAfterSuccess() async throws {
        let account = OpenAIAccountProfile(
            id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            name: "Work",
            isEnabled: true,
            storage: .managed
        )
        let authenticator = RecordingOpenAIAuthenticator()
        let model = MenuBarViewModel(
            store: UsageStore(clients: [], pollIntervalSeconds: 3_600),
            openAIAccounts: [.defaultAccount(), account],
            openAIAuthenticator: authenticator
        )

        model.loginOpenAIAccount(id: account.id)
        try await Task.sleep(nanoseconds: 50_000_000)

        let loginIDs = await authenticator.loginIDs
        XCTAssertEqual(loginIDs, [account.id])
        XCTAssertEqual(model.openAIAccountLoginStates[account.id], .idle)
    }

    func test_localCallbackServerReceivesAndRespondsToBrowserRedirect() async throws {
        let server = try OpenAILocalCallbackServer(port: 0)
        try await server.start()
        defer { server.cancel() }
        async let receivedCallback = server.waitForCallback()
        let callbackURL = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(server.port)/auth/callback?code=test-code&state=test-state")
        )
        let browserRequest = Task {
            try await URLSession.shared.data(from: callbackURL)
        }

        let callback = try await receivedCallback
        XCTAssertEqual(callback.code, "test-code")
        XCTAssertEqual(callback.state, "test-state")
        server.respond(to: callback, success: true, message: "Connected")

        let (data, response) = try await browserRequest.value
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("Connected") == true)
    }

    func test_callbackParserExtractsCodeAndStateWithoutLoggingSecrets() throws {
        let connection = NWConnection(host: "localhost", port: 1455, using: .tcp)
        let callback = try OpenAILocalCallbackServer.parseCallbackRequest(
            "GET /auth/callback?code=secret-code&state=expected HTTP/1.1\r\nHost: localhost\r\n\r\n",
            connection: connection
        )

        XCTAssertEqual(callback.code, "secret-code")
        XCTAssertEqual(callback.state, "expected")
        XCTAssertNil(callback.error)
    }

    private func jwt(_ claims: [String: Any]) -> String {
        let header = try! JSONSerialization.data(withJSONObject: ["alg": "none"])
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        return "\(header.base64URLEncodedString()).\(payload.base64URLEncodedString()).signature"
    }
}

private actor RecordingOpenAIAuthenticator: OpenAIAccountAuthenticating {
    private(set) var loginIDs: [String] = []

    func login(account: OpenAIAccountProfile) {
        self.loginIDs.append(account.id)
    }

    func cancel(accountID _: String) {}
}
