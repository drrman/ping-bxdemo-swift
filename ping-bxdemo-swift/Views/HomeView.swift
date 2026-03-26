import SwiftUI

struct HomeView: View {
    private let config = CustomerConfig.current

    var body: some View {
        VStack {
            Text("Home")
                .font(.largeTitle)
                .foregroundColor(config.primaryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    HomeView()
}
