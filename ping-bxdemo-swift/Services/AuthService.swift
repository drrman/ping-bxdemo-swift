import Foundation

class AuthService: ObservableObject {
    private let config = PingConfig.current

    @Published var isAuthenticated = false
    @Published var accessToken: String?

    // TODO: Implement DaVinci flow integration
}
