import CryptoKit
import Foundation
import Security

/// PKCE generation used by the OpenAI browser authorization shell.
enum OpenAIPKCE {
    struct Codes: Sendable, Equatable {
        let verifier: String
        let challenge: String
    }

    static func generate() throws -> Codes {
        let verifier = try self.randomURLSafeString(byteCount: 64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Codes(
            verifier: verifier,
            challenge: Data(digest).base64URLEncodedString()
        )
    }

    static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw OpenAIOAuthLoginError.invalidCallback
        }
        return Data(bytes).base64URLEncodedString()
    }
}
