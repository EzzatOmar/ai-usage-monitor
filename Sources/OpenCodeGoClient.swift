import Foundation

/// Effectful shell: credential discovery and a single read-only usage request.
struct OpenCodeGoClient: ProviderClient {
    let providerID: ProviderID = .openCodeGo
    private let loadAPIKey: @Sendable () -> String?
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(
        loadAPIKey: @escaping @Sendable () -> String? = { Self.discoverAPIKey() },
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
            try await URLSession.shared.data(for: $0)
        }
    ) {
        self.loadAPIKey = loadAPIKey
        self.transport = transport
    }

    func fetchUsage(now: Date, mode _: UsageRefreshMode) async -> ProviderUsageResult {
        guard let key = self.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return ProviderUsageResult(provider: self.providerID, lastUpdated: now, errorState: .authNeeded)
        }
        do {
            var request = URLRequest(url: URL(string: "https://opencode.ai/zen/go/v1/usage")!)
            request.httpMethod = "GET"
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("AIUsageMonitor", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await self.transport(request)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderErrorState.networkError("OpenCode Go returned no HTTP response.")
            }
            switch http.statusCode {
            case 200...299:
                return try OpenCodeGoUsageCore.decodeUsage(data, now: now)
            case 401:
                throw ProviderErrorState.tokenExpired
            case 403:
                let error = try? JSONDecoder().decode(APIError.self, from: data)
                if error?.error.type == "EntitlementError" {
                    throw ProviderErrorState.endpointError("This key requires an active OpenCode Go subscription.")
                }
                throw ProviderErrorState.endpointError("OpenCode Go denied access (HTTP 403). Check the key or try again later.")
            case 429:
                throw ProviderErrorState.rateLimited("OpenCode Go usage API is rate limited.", retryAfter: http.retryAfterTimeInterval)
            default:
                throw ProviderErrorState.endpointError("OpenCode Go usage request failed (HTTP \(http.statusCode)).")
            }
        } catch let error as ProviderErrorState {
            return ProviderUsageResult(provider: self.providerID, lastUpdated: now, errorState: error)
        } catch {
            // Never surface an arbitrary transport description that might contain a key.
            return ProviderUsageResult(
                provider: self.providerID, lastUpdated: now,
                errorState: .networkError("Could not reach OpenCode Go. Check your connection and try again.")
            )
        }
    }

    static func discoverAPIKey() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let stored = AuthStore.loadOpenCodeGoAPIKey()
        if let key = OpenCodeGoUsageCore.selectAPIKey(
            stored: stored, environment: environment["OPENCODE_GO_API_KEY"], authData: nil
        ) { return key }
        return OpenCodeGoUsageCore.selectAPIKey(
            stored: nil, environment: nil,
            authData: try? Data(contentsOf: LocalPaths.openCodeAuthPath(env: environment))
        )
    }

    private struct APIError: Decodable {
        let error: Detail
        struct Detail: Decodable {
            let type: String
        }
    }
}
