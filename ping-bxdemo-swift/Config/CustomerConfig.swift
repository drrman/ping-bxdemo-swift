import SwiftUI

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
        customerSlug: "southwest-airlines"
    )
}
