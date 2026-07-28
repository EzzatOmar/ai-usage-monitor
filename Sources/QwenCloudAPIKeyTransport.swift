import Foundation

@MainActor
final class QwenCloudAPIKeyTransport: QwenCloudUsageTransport {
    static let shared = QwenCloudAPIKeyTransport()

    static let modelsURL = URL(
        string: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/models"
    )!

    private var validatedAPIKey: String?

    private init() {}

    func fetchUsagePayload() async throws -> Data {
        guard let apiKey = AuthStore.loadQwenCloudAPIKey() else {
            throw ProviderErrorState.authNeeded
        }

        try await self.validateAPIKey(apiKey)
        throw ProviderErrorState.endpointError(
            "API key verified. QwenCloud does not expose Token Plan Individual quota through API-key authentication."
        )
    }

    func clearCachedValidation() {
        self.validatedAPIKey = nil
    }

    static func makeAPIKeyValidationRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: Self.modelsURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validateAPIKey(_ apiKey: String) async throws {
        guard apiKey.hasPrefix("sk-sp-") else {
            throw ProviderErrorState.authNeeded
        }
        guard self.validatedAPIKey != apiKey else { return }

        let (_, response) = try await URLSession.shared.data(
            for: Self.makeAPIKeyValidationRequest(apiKey: apiKey)
        )
        guard let http = response as? HTTPURLResponse else {
            throw ProviderErrorState.endpointError("Invalid QwenCloud API key validation response")
        }
        switch http.statusCode {
        case 200:
            self.validatedAPIKey = apiKey
        case 401, 403:
            self.validatedAPIKey = nil
            throw ProviderErrorState.tokenExpired
        case 429:
            throw ProviderErrorState.rateLimited("HTTP 429", retryAfter: http.retryAfterTimeInterval)
        default:
            throw ProviderErrorState.endpointError("API key validation HTTP \(http.statusCode)")
        }
    }
}
