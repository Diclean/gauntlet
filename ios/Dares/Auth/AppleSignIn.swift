import AuthenticationServices
import CryptoKit
import Foundation
import Security
import SwiftUI

/// Nonce helpers for Sign in with Apple.
///
/// The raw nonce is generated on the device, hashed with SHA-256 and handed to Apple; the raw
/// value travels to our own server, which hashes it again and compares it with the `nonce` claim
/// of Apple's identity token.
enum AppleNonce {
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")

    static func random(length: Int = 32) -> String {
        var result = ""
        var bytes = [UInt8](repeating: 0, count: 32)
        while result.count < length {
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                // Fall back to a time based nonce; it is still unique enough for one request.
                return String(UUID().uuidString.replacingOccurrences(of: "-", with: ""))
            }
            for byte in bytes where result.count < length {
                let character = charset[Int(byte) % charset.count]
                result.append(character)
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct AppleSignInResult: Sendable {
    let identityToken: String
    let rawNonce: String
    let displayName: String?
}

enum AppleSignInError: LocalizedError, Sendable {
    case missingCredential
    case missingNonce
    case missingIdentityToken

    var errorDescription: String? {
        switch self {
        case .missingCredential:
            return String(localized: "error.apple_credential")
        case .missingNonce:
            return String(localized: "error.apple_nonce")
        case .missingIdentityToken:
            return String(localized: "error.apple_identity_token")
        }
    }
}

/// The Sign in with Apple button. The raw nonce is kept in `@State` so it can be sent to our
/// server right after the credential arrives.
struct AppleSignInButton: View {
    let onResult: (Result<AppleSignInResult, Error>) -> Void

    @State private var currentNonce: String?

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            let rawNonce = AppleNonce.random()
            currentNonce = rawNonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleNonce.sha256(rawNonce)
        } onCompletion: { result in
            switch result {
            case let .success(authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    onResult(.failure(AppleSignInError.missingCredential))
                    return
                }
                guard let identityToken = credential.identityToken else {
                    onResult(.failure(AppleSignInError.missingIdentityToken))
                    return
                }
                guard let rawNonce = currentNonce else {
                    onResult(.failure(AppleSignInError.missingNonce))
                    return
                }
                let name = credential.fullName.map { fullName(from: $0) }
                onResult(
                    .success(
                        AppleSignInResult(
                            identityToken: identityToken.base64EncodedString(),
                            rawNonce: rawNonce,
                            displayName: name
                        )
                    )
                )
                currentNonce = nil
            case let .failure(error):
                let code = (error as? ASAuthorizationError)?.code
                if code == .canceled { return }
                onResult(.failure(error))
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func fullName(from personName: PersonNameComponents) -> String {
        let formatted = PersonNameComponentsFormatter().string(from: personName)
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
