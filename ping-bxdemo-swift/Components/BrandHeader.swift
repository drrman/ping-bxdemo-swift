import SwiftUI

struct BrandHeader: View {
    private let config = CustomerConfig.current

    var body: some View {
        VStack(spacing: 8) {
            if let uiImage = UIImage(named: config.logoAssetName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 60)
            } else {
                Image(systemName: "lock.shield.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 60)
                    .foregroundColor(config.primaryColor)
            }
            Text(config.appName.isEmpty ? "BXDemo" : config.appName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(config.primaryColor)
            Text(config.tagline.isEmpty ? "Secure identity powered by Ping Identity" : config.tagline)
                .font(.subheadline)
                .foregroundColor(config.secondaryColor)
        }
        .padding()
    }
}

#Preview {
    BrandHeader()
}
