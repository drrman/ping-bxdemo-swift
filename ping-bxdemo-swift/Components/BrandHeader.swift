import SwiftUI

struct BrandHeader: View {
    private let config = CustomerConfig.current

    var body: some View {
        VStack(spacing: 8) {
            Image(config.logoAssetName)
                .resizable()
                .scaledToFit()
                .frame(height: 60)
            Text(config.appName)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(config.primaryColor)
            Text(config.tagline)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#Preview {
    BrandHeader()
}
