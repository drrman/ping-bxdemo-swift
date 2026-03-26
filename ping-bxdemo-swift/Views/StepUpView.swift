import SwiftUI

struct StepUpView: View {
    private let config = CustomerConfig.current

    var body: some View {
        VStack {
            Text("Step-Up Authentication")
                .font(.largeTitle)
                .foregroundColor(config.primaryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    StepUpView()
}
