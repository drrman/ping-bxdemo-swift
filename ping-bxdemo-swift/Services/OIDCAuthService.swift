import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
class OIDCAuthService: NSObject, ObservableObject {

    private let config = PingConfig.current
    private let customerConfig = CustomerConfig.current

    // PKCE state
    private var codeVerifier: String = ""

    // MARK: - Public API

    /// Start the OIDC login flow via ASWebAuthenticationSession
    func startLogin(authService: AuthService) async throws {
        let (verifier, challenge) = generatePKCE()
        self.codeVerifier = verifier

        let authURL = buildAuthorizationURL(
            challenge: challenge,
            hint: nil
        )

        let code = try await presentAuthSession(url: authURL)
        let tokens = try await exchangeCodeForTokens(code: code)
        authService.storeTokens(
            accessToken: tokens.accessToken,
            idToken: tokens.idToken,
            refreshToken: tokens.refreshToken
        )
        authService.isAuthenticated = true
    }

    // MARK: - PKCE Generation

    private func generatePKCE() -> (verifier: String, challenge: String) {
        // Generate a cryptographically random code verifier
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        let verifier = Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        // Generate code challenge as SHA256 hash of verifier
        let challengeData = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(challengeData).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        return (verifier, challenge)
    }

    // MARK: - Authorization URL

    private func buildAuthorizationURL(challenge: String, hint: String?) -> URL {
        let base = "https://auth.pingone.com/\(config.environmentId)/as/authorize"
        var components = URLComponents(string: base)!

        var params: [URLQueryItem] = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectUri),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "login"),
        ]

        // If loginPolicyId is set, use it as acr_values
        if !config.loginPolicyId.isEmpty {
            params.append(URLQueryItem(name: "acr_values", value: config.loginPolicyId))
        }

        if let hint = hint {
            params.append(URLQueryItem(name: "login_hint", value: hint))
        }

        components.queryItems = params
        return components.url!
    }

    // MARK: - ASWebAuthenticationSession

    private func presentAuthSession(url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let callbackScheme = "bxdemo"

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL,
                                                    resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: {
                          $0.name == "code"
                      })?.value else {
                    continuation.resume(throwing: OIDCError.noAuthorizationCode)
                    return
                }

                continuation.resume(returning: code)
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            session.start()
        }
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String) async throws -> TokenResponse {
        let tokenURL = URL(string:
            "https://auth.pingone.com/\(config.environmentId)/as/token")!

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded",
                        forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type": "authorization_code",
            "client_id": config.clientId,
            "code": code,
            "redirect_uri": config.redirectUri,
            "code_verifier": codeVerifier
        ]

        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OIDCError.tokenExchangeFailed
        }

        let json = try JSONDecoder().decode(TokenResponse.self, from: data)
        return json
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OIDCAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        DispatchQueue.main.sync {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

// MARK: - Supporting Types

enum OIDCError: LocalizedError {
    case noAuthorizationCode
    case tokenExchangeFailed

    var errorDescription: String? {
        switch self {
        case .noAuthorizationCode:
            return "No authorization code received"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for tokens"
        }
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let idToken: String?
    let refreshToken: String?
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case idToken = "id_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}
