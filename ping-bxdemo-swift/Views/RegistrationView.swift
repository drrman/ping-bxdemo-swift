import SwiftUI
import PingDavinci
import PingOidc
import PingOrchestrate

@MainActor
class RegistrationViewModel: ObservableObject {
    @Published var currentNode: Node?
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var registrationComplete = false

    private let daVinci: DaVinci

    init() {
        let pingConfig = PingConfig.current
        self.daVinci = DaVinci.createDaVinci { daVinciConfig in
            daVinciConfig.module(PingDavinci.OidcModule.config) { oidcValue in
                oidcValue.clientId = pingConfig.clientId
                oidcValue.scopes = Set(pingConfig.scopes)
                oidcValue.redirectUri = pingConfig.redirectUri
                oidcValue.discoveryEndpoint = "https://auth.pingone.com/\(pingConfig.environmentId)/as/.well-known/openid-configuration"
                oidcValue.additionalParameters = ["prompt": "login"]
            }
        }
    }

    func startFlow() async {
        isLoading = true
        errorMessage = nil
        let node = await daVinci.start()
        await handleNode(node)
    }

    func handleNode(_ node: Node) async {
        isLoading = false
        switch node {
        case let continueNode as ContinueNode:
            self.currentNode = continueNode
            self.errorMessage = nil

        case is SuccessNode:
            self.registrationComplete = true

        case let errorNode as ErrorNode:
            self.errorMessage = errorNode.message
            self.currentNode = errorNode.continueNode

        case let failureNode as FailureNode:
            self.errorMessage = "Registration failed: \(failureNode.cause.localizedDescription)"
            await startFlow()

        default:
            self.errorMessage = "Unexpected response"
        }
    }

    func submitNode(_ continueNode: ContinueNode) async {
        isLoading = true
        errorMessage = nil
        let nextNode = await continueNode.next()
        await handleNode(nextNode)
    }
}

struct RegistrationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RegistrationViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                BrandHeader()

                if viewModel.registrationComplete {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        Text("Registration Complete")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Redirecting to sign in...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 40)
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        dismiss()
                    }
                } else {
                    if viewModel.isLoading {
                        ProgressView("Connecting...")
                            .padding(.top, 40)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if let continueNode = viewModel.currentNode as? ContinueNode, !viewModel.isLoading {
                        DaVinciFormView(node: continueNode) { node in
                            Task {
                                await viewModel.submitNode(node)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Button("Back to Sign In") {
                        dismiss()
                    }
                    .font(.callout)
                    .foregroundColor(CustomerConfig.current.primaryColor)
                    .padding(.top, 8)
                }
            }
            .padding(.top, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
        .task {
            await viewModel.startFlow()
        }
    }
}

#Preview {
    NavigationStack {
        RegistrationView()
    }
}
