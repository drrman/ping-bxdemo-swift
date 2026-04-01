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

    func startStepUp(userId: String) async {
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

        // Auto-populate userId on the first node and submit automatically
        if let continueNode = node as? ContinueNode {
            for collector in continueNode.collectors {
                if let textCollector = collector as? TextCollector,
                   textCollector.key == "userId" {
                    textCollector.value = userId
                }
            }
            let nextNode = await continueNode.next()
            await handleNode(nextNode)
        } else {
            await handleNode(node)
        }
    }

    func handleNode(_ node: Node) async {
        isLoading = false
        switch node {
        case let continueNode as ContinueNode:
            // Check for stepUpComplete in the response
            if let stepUpComplete = continueNode.input["stepUpComplete"] as? String,
               stepUpComplete == "true" {
                self.isVerified = true
                return
            }
            if let success = continueNode.input["success"] as? Bool, success,
               continueNode.input["stepUpComplete"] != nil {
                self.isVerified = true
                return
            }
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

    let tileTitle: String
    let tileSubtitle: String
    let userId: String

    /// Whether the current node is a "Choose Verification Method" screen
    private var isVerificationMethodNode: Bool {
        guard let continueNode = viewModel.currentNode as? ContinueNode else { return false }
        return continueNode.collectors.contains { collector in
            (collector as? TextCollector)?.key == "verificationMethod"
        }
    }

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
                        // Success screen
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)

                            Text("Identity Verified")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("You now have access to this secure area")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            VStack(spacing: 4) {
                                Text(tileTitle)
                                    .font(.headline)
                                    .foregroundColor(config.primaryColor)
                                Text(tileSubtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 8)

                            PingButton(title: "Done") {
                                dismiss()
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)
                        }
                        .padding(.top, 20)
                    } else {
                        if viewModel.isLoading {
                            ProgressView("Verifying...")
                                .padding(.top, 20)
                        }

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            Button("Dismiss") {
                                dismiss()
                            }
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(config.primaryColor)
                            .padding(.top, 4)
                        }

                        if let continueNode = viewModel.currentNode as? ContinueNode, !viewModel.isLoading {
                            if isVerificationMethodNode {
                                // Render verification method choice as two buttons
                                VStack(spacing: 12) {
                                    Text("Choose Verification Method")
                                        .font(.headline)

                                    PingButton(title: "Send SMS Code") {
                                        setVerificationMethodAndSubmit(continueNode, value: "sms")
                                    }
                                    .padding(.horizontal)

                                    PingButton(title: "Send Email Code") {
                                        setVerificationMethodAndSubmit(continueNode, value: "email")
                                    }
                                    .padding(.horizontal)
                                }
                            } else {
                                DaVinciFormView(node: continueNode) { node in
                                    Task {
                                        await viewModel.submitNode(node)
                                    }
                                }
                                .padding(.horizontal)
                            }
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
            await viewModel.startStepUp(userId: userId)
        }
    }

    private func setVerificationMethodAndSubmit(_ node: ContinueNode, value: String) {
        for collector in node.collectors {
            if let textCollector = collector as? TextCollector,
               textCollector.key == "verificationMethod" {
                textCollector.value = value
            }
        }
        Task {
            await viewModel.submitNode(node)
        }
    }
}

#Preview {
    StepUpView(tileTitle: "Travel Documents", tileSubtitle: "Passport and security", userId: "test-user-id")
}
