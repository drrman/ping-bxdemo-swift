import SwiftUI
import PingDavinci
import PingOidc
import PingOrchestrate

@MainActor
class StepUpViewModel: ObservableObject {
    @Published var currentNode: Node?
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var isVerified = false
    @Published var notConfigured = false

    private var daVinci: DaVinci?
    var onSuccess: (() -> Void)?

    func startFlow() async {
        let pingConfig = PingConfig.current

        guard !pingConfig.stepUpPolicyId.isEmpty else {
            isLoading = false
            notConfigured = true
            return
        }

        let dv = DaVinci.createDaVinci { daVinciConfig in
            daVinciConfig.module(PingDavinci.OidcModule.config) { oidcValue in
                oidcValue.clientId = pingConfig.clientId
                oidcValue.scopes = Set(pingConfig.scopes)
                oidcValue.redirectUri = pingConfig.redirectUri
                oidcValue.discoveryEndpoint = "https://auth.pingone.com/\(pingConfig.environmentId)/as/.well-known/openid-configuration"
                oidcValue.additionalParameters = ["prompt": "login"]
            }
        }
        self.daVinci = dv

        isLoading = true
        errorMessage = nil
        let node = await dv.start()
        await handleNode(node)
    }

    func handleNode(_ node: Node) async {
        isLoading = false
        switch node {
        case let continueNode as ContinueNode:
            self.currentNode = continueNode
            self.errorMessage = nil

        case is SuccessNode:
            self.isVerified = true

        case let errorNode as ErrorNode:
            self.errorMessage = errorNode.message
            self.currentNode = errorNode.continueNode

        case let failureNode as FailureNode:
            self.errorMessage = "Verification failed: \(failureNode.cause.localizedDescription)"

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

struct StepUpView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = StepUpViewModel()
    private let config = CustomerConfig.current
    var onSuccess: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Lock icon
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48))
                        .foregroundColor(config.primaryColor)
                        .padding(.top, 20)

                    // Title and subtitle
                    VStack(spacing: 8) {
                        Text(config.stepUpTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(config.stepUpSubtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if viewModel.notConfigured {
                        VStack(spacing: 12) {
                            Image(systemName: "gear.badge.xmark")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("Step-Up flow not configured")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Set stepUpPolicyId in PingConfig to enable this feature.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                    } else if viewModel.isVerified {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)
                            Text("Identity Verified")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        .padding(.top, 20)
                        .task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            onSuccess?()
                            dismiss()
                        }
                    } else {
                        if viewModel.isLoading {
                            ProgressView("Connecting...")
                                .padding(.top, 20)
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
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Color(.systemBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(config.primaryColor)
                }
            }
        }
        .task {
            await viewModel.startFlow()
        }
    }
}

#Preview {
    StepUpView()
}
