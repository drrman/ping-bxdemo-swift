import SwiftUI

@main
struct ping_bxdemo_swiftApp: App {
    @StateObject private var authService = AuthService.shared

    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                NavigationStack {
                    HomeView()
                }
                .environmentObject(authService)
            } else {
                LoginView()
                    .environmentObject(authService)
            }
        }
    }
}
