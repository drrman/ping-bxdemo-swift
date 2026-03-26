import SwiftUI

struct LoginView: View {
    private let config = CustomerConfig.current

    var body: some View {
        VStack {
            Text("Login")
                .font(.largeTitle)
                .foregroundColor(config.primaryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    LoginView()
}
