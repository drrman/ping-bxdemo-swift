import Foundation
import Security

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isAuthenticated = false
    @Published var accessToken: String?

    private let serviceName = "com.ping.bxdemo"

    func storeTokens(accessToken: String, idToken: String?, refreshToken: String?) {
        setKeychainValue(accessToken, forKey: "accessToken")
        if let idToken { setKeychainValue(idToken, forKey: "idToken") }
        if let refreshToken { setKeychainValue(refreshToken, forKey: "refreshToken") }
        self.accessToken = accessToken
        self.isAuthenticated = true
    }

    func getStoredAccessToken() -> String? {
        getKeychainValue(forKey: "accessToken")
    }

    func getStoredIdToken() -> String? {
        getKeychainValue(forKey: "idToken")
    }

    func clearTokens() {
        deleteKeychainValue(forKey: "accessToken")
        deleteKeychainValue(forKey: "idToken")
        deleteKeychainValue(forKey: "refreshToken")
        accessToken = nil
        isAuthenticated = false
    }

    func getUserFromToken() -> [String: Any]? {
        guard let idToken = getStoredIdToken() else { return nil }
        let segments = idToken.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var base64 = String(segments[1])
        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    // MARK: - Keychain Helpers

    private func setKeychainValue(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        deleteKeychainValue(forKey: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func getKeychainValue(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainValue(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
