import SwiftUI

enum AuthMode {
    case davinci
    case oidcRedirect
}

struct ContentTile: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    enum TileAction { case navigate, stepUp }
    let action: TileAction
}

struct CustomerConfig {
    let authMode: AuthMode
    let appName: String
    let tagline: String
    let primaryColor: Color
    let secondaryColor: Color
    let buttonColor: Color
    let buttonBgColor: Color
    let footerBgColor: Color
    let homeBannerColor: Color
    let logoAssetName: String
    let bannerAssetName: String
    let vertical: String
    let customerSlug: String
    let contentTiles: [ContentTile]
    let stepUpTitle: String
    let stepUpSubtitle: String
}

extension CustomerConfig {
    static let current = CustomerConfig(
        authMode: .davinci,
        appName: "",
        tagline: "",
        primaryColor: Color(hex: "#304CB2"),
        secondaryColor: Color(hex: "#FFBF27"),
        buttonColor: Color(hex: "#FFFFFF"),
        buttonBgColor: Color(hex: "#304CB2"),
        footerBgColor: Color(hex: "#304CB2"),
        homeBannerColor: Color(hex: "#FFBF27"),
        logoAssetName: "logo",
        bannerAssetName: "banner",
        vertical: "airlines",
        customerSlug: "",
        contentTiles: [
            ContentTile(
                title: "My Trips",
                subtitle: "View and manage your upcoming flights",
                icon: "airplane",
                action: .navigate
            ),
            ContentTile(
                title: "Rapid Rewards",
                subtitle: "You have 24,500 points — redeem for your next trip",
                icon: "star.fill",
                action: .navigate
            ),
            ContentTile(
                title: "Flight Deals",
                subtitle: "Exclusive member offers available now",
                icon: "tag.fill",
                action: .navigate
            ),
            ContentTile(
                title: "Travel Documents",
                subtitle: "Passport and security",
                icon: "lock.shield.fill",
                action: .stepUp
            )
        ],
        stepUpTitle: "Verify Your Identity",
        stepUpSubtitle: "This section requires additional verification"
    )
}
