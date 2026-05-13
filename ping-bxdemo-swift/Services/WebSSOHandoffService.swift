import Foundation
import CryptoKit

enum WebSSOHandoffError: LocalizedError {
    case missingAccessToken
    case ipFetchFailed
    case parRequestFailed(status: Int, body: String)
    case invalidPARResponse
    case invalidAuthorizeURL

    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            return "No access token available. Please sign in again."
        case .ipFetchFailed:
            return "Failed to fetch public IP address."
        case .parRequestFailed(let status, let body):
            return "PAR request failed (HTTP \(status)): \(body)"
        case .invalidPARResponse:
            return "PAR response did not contain a request_uri."
        case .invalidAuthorizeURL:
            return "Failed to build the authorize URL."
        }
    }
}

class WebSSOHandoffService {
    private let environmentId = "e08cdcdf-2389-418f-9064-aaa9ee4c5150"
    private let clientId = "77031fdc-e3e6-4f02-8e8e-a8aeb4be332a"
    private let scope = "openid"
    private let redirectUri = "https://unused"
    private let applicationURL = "https://bxdemo-insulet.netlify.app/"

    func startHandoff() async throws -> URL {
        print("[WebSSOHandoff] Starting handoff")

        guard let accessToken = await AuthService.shared.getStoredAccessToken(),
              !accessToken.isEmpty else {
            print("[WebSSOHandoff] No access token in Keychain")
            throw WebSSOHandoffError.missingAccessToken
        }
        print("[WebSSOHandoff] Got access token (\(accessToken.count) chars)")
        print("[WebSSOHandoff] FULL TOKEN: \(accessToken)")

        // Write token to a file so we can read it from terminal
        let fileManager = FileManager.default
        if let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = docsDir.appendingPathComponent("debug-token.txt")
            try? accessToken.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.codeChallenge(forVerifier: codeVerifier)
        print("[WebSSOHandoff] PKCE verifier/challenge generated")

        let ipAddress = try await fetchPublicIP()
        print("[WebSSOHandoff] Public IP: \(ipAddress)")

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let expMs = nowMs + 10_000

        let form: [String: String] = [
            "client_id": clientId,
            "response_type": "code",
            "scope": scope,
            "redirect_uri": redirectUri,
            "request_token": accessToken,
            "code_challenge": codeChallenge,
            "code_challenge_method": "S256",
            "ip_address": ipAddress,
            "request_timestamp": String(nowMs),
            "exp": String(expMs),
            "application_URL": applicationURL
        ]

        let requestUri = try await postPAR(form: form)
        print("[WebSSOHandoff] Got request_uri: \(requestUri)")

        guard let encodedRequestUri = requestUri.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed),
              let encodedClientId = clientId.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed),
              let url = URL(string: "https://auth.pingone.com/\(environmentId)/as/authorize?client_id=\(encodedClientId)&request_uri=\(encodedRequestUri)") else {
            print("[WebSSOHandoff] Failed to build authorize URL")
            throw WebSSOHandoffError.invalidAuthorizeURL
        }

        print("[WebSSOHandoff] Authorize URL: \(url.absoluteString)")
        return url
    }

    private func fetchPublicIP() async throws -> String {
        guard let url = URL(string: "https://api.ipify.org") else {
            throw WebSSOHandoffError.ipFetchFailed
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ip.isEmpty else {
            throw WebSSOHandoffError.ipFetchFailed
        }
        return ip
    }

    private func postPAR(form: [String: String]) async throws -> String {
        guard let url = URL(string: "https://auth.pingone.com/\(environmentId)/as/par") else {
            throw WebSSOHandoffError.invalidPARResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formURLEncode(form).data(using: .utf8)

        print("[WebSSOHandoff] POST \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw WebSSOHandoffError.invalidPARResponse
        }
        let bodyString = String(data: data, encoding: .utf8) ?? ""
        print("[WebSSOHandoff] PAR response status: \(http.statusCode)")
        print("[WebSSOHandoff] PAR response body: \(bodyString)")

        guard (200..<300).contains(http.statusCode) else {
            throw WebSSOHandoffError.parRequestFailed(status: http.statusCode, body: bodyString)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let requestUri = json["request_uri"] as? String, !requestUri.isEmpty else {
            throw WebSSOHandoffError.invalidPARResponse
        }
        return requestUri
    }

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(forVerifier verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    private static func formURLEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
