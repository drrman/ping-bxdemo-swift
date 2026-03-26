import SwiftUI

struct RegistrationView: View {
    private let config = CustomerConfig.current

    var body: some View {
        VStack {
            Text("Registration")
                .font(.largeTitle)
                .foregroundColor(config.primaryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    RegistrationView()
}
