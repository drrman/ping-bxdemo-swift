import SwiftUI

struct PingButton: View {
    let title: String
    let action: () -> Void
    private let config = CustomerConfig.current

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundColor(config.buttonColor)
                .frame(maxWidth: .infinity)
                .padding()
                .background(config.buttonBgColor)
                .cornerRadius(10)
        }
    }
}

#Preview {
    PingButton(title: "Sign In") {}
        .padding()
}
