import SwiftUI

struct HomeView: View {
    private let config = CustomerConfig.current
    @State private var selectedTab = 0
    @State private var showStepUp = false
    @State private var stepUpSucceeded = false

    private var firstName: String {
        guard let claims = AuthService.shared.getUserFromToken() else { return "" }
        if let givenName = claims["given_name"] as? String, !givenName.isEmpty {
            return givenName
        }
        if let name = claims["name"] as? String, !name.isEmpty {
            return String(name.split(separator: " ").first ?? "")
        }
        return ""
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            homeContent
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)

            ProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
                .tag(1)
        }
        .tint(config.primaryColor)
    }

    private var homeContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                BrandHeader()
                    .padding(.bottom, 8)

                // Hero banner
                ZStack(alignment: .bottom) {
                    if UIImage(named: config.bannerAssetName) != nil {
                        Image(config.bannerAssetName)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                            .clipped()
                    } else {
                        config.homeBannerColor
                            .frame(height: 200)
                    }

                    Text(config.tagline)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(config.primaryColor.opacity(0.75))
                }
                .clipped()

                // Welcome message
                if !firstName.isEmpty {
                    Text("Welcome back, \(firstName)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 20)
                        .padding(.bottom, 4)
                }

                // Content tiles
                VStack(spacing: 12) {
                    ForEach(Array(config.contentTiles.enumerated()), id: \.offset) { _, tile in
                        ContentTileCard(tile: tile) {
                            if tile.icon == "lock.shield.fill" {
                                showStepUp = true
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemBackground))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    selectedTab = 1
                } label: {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundColor(config.primaryColor)
                }
            }
        }
        .sheet(isPresented: $showStepUp) {
            StepUpView {
                stepUpSucceeded = true
            }
        }
        .alert("Coming Soon", isPresented: $stepUpSucceeded) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Travel Documents will be available in a future update.")
        }
    }
}

private struct ContentTileCard: View {
    let tile: ContentTile
    var onTap: (() -> Void)? = nil
    private let config = CustomerConfig.current

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: tile.icon)
                    .font(.title2)
                    .foregroundColor(config.secondaryColor)
                    .frame(width: 44, height: 44)
                    .background(config.primaryColor.opacity(0.1))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tile.title)
                        .font(.headline)
                        .foregroundColor(config.primaryColor)
                    Text(tile.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(AuthService.shared)
    }
}
