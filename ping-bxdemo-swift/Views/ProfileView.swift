import SwiftUI

struct ProfileView: View {
    private let config = CustomerConfig.current

    var body: some View {
        VStack {
            Text("Profile")
                .font(.largeTitle)
                .foregroundColor(config.primaryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    ProfileView()
}
