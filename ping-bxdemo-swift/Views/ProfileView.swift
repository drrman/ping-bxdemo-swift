import SwiftUI

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var fullName: String = ""
    @Published var email: String = ""
    @Published var sub: String = ""
    @Published var truncatedAccessToken: String = ""
    @Published var claims: [(key: String, value: String)] = []

    func loadProfile() {
        guard let tokenClaims = AuthService.shared.getUserFromToken() else { return }

        if let name = tokenClaims["name"] as? String, !name.isEmpty {
            fullName = name
        } else {
            let given = tokenClaims["given_name"] as? String ?? ""
            let family = tokenClaims["family_name"] as? String ?? ""
            fullName = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        }

        email = tokenClaims["email"] as? String ?? ""
        sub = tokenClaims["sub"] as? String ?? ""

        if let accessToken = AuthService.shared.getStoredAccessToken() {
            if accessToken.count > 20 {
                truncatedAccessToken = String(accessToken.prefix(20)) + "..."
            } else {
                truncatedAccessToken = accessToken
            }
        }

        claims = tokenClaims
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, value: String(describing: $0.value)) }
    }

    var initials: String {
        let parts = fullName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.map { String($0) }.joined().uppercased()
    }
}

struct ProfileView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var viewModel = ProfileViewModel()
    @State private var claimsExpanded = false
    private let config = CustomerConfig.current

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                BrandHeader()

                // Avatar circle with initials
                ZStack {
                    Circle()
                        .fill(config.primaryColor)
                        .frame(width: 100, height: 100)
                    Text(viewModel.initials)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                }

                // Name and email
                VStack(spacing: 4) {
                    Text(viewModel.fullName)
                        .font(.title)
                        .fontWeight(.bold)
                    Text(viewModel.email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Token Claims section
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation { claimsExpanded.toggle() }
                    } label: {
                        HStack {
                            Text("Token Claims")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: claimsExpanded ? "chevron.up" : "chevron.down")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }

                    if claimsExpanded {
                        VStack(spacing: 0) {
                            ForEach(viewModel.claims, id: \.key) { claim in
                                HStack(alignment: .top) {
                                    Text(claim.key)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .leading)
                                    Text(claim.value)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .lineLimit(3)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                Divider()
                            }
                        }
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(10)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal)

                // Access Token row
                VStack(alignment: .leading, spacing: 4) {
                    Text("Access Token")
                        .font(.headline)
                    Text(viewModel.truncatedAccessToken)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)

                // Sign Out button
                PingButton(title: "Sign Out") {
                    authService.clearTokens()
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadProfile()
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
            .environmentObject(AuthService.shared)
    }
}
