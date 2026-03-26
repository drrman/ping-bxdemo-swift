import SwiftUI

struct ContentTile {
    let icon: String
    let title: String
    let subtitle: String
}

struct CustomerConfig {
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

    static let current = CustomerConfig(
        appName: "Southwest Airlines",
        tagline: "Without a heart, it's just a machine.",
        primaryColor: Color(hex: "#304CB2"),
        secondaryColor: Color(hex: "#FFBF27"),
        buttonColor: Color(hex: "#FFFFFF"),
        buttonBgColor: Color(hex: "#304CB2"),
        footerBgColor: Color(hex: "#304CB2"),
        homeBannerColor: Color(hex: "#FFBF27"),
        logoAssetName: "logo",
        bannerAssetName: "banner",
        vertical: "airlines",
        customerSlug: "southwest-airlines",
        contentTiles: [
            ContentTile(icon: "airplane", title: "My Trips", subtitle: "View and manage your upcoming flights"),
            ContentTile(icon: "star.fill", title: "Rapid Rewards", subtitle: "You have 24,500 points — redeem for your next trip"),
            ContentTile(icon: "tag.fill", title: "Flight Deals", subtitle: "Exclusive member offers available now"),
            ContentTile(icon: "lock.shield.fill", title: "Travel Documents", subtitle: "Passport and secure ID management"),
        ],
        stepUpTitle: "Verify Your Identity",
        stepUpSubtitle: "Additional verification is required to access this feature"
    )
}
