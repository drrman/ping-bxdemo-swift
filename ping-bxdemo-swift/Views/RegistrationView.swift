import SwiftUI
import PingDavinci
import PingOidc
import PingOrchestrate
import PingProtect

// MARK: - RegistrationViewModel

@MainActor
class RegistrationViewModel: ObservableObject {
    @Published var state: DavinciState = DavinciState()
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    @Published var isComplete: Bool = false

    private let daVinci: DaVinci

    init() {
        let pingConfig = PingConfig.current
        print("[RegistrationVM] Starting with registrationPolicyId: \(pingConfig.registrationPolicyId)")
        self.daVinci = DaVinci.createDaVinci { daVinciConfig in
            daVinciConfig.module(PingDavinci.OidcModule.config) { oidcValue in
                oidcValue.clientId = pingConfig.clientId
                oidcValue.scopes = Set(pingConfig.scopes)
                oidcValue.redirectUri = pingConfig.redirectUri
                oidcValue.discoveryEndpoint = "https://auth.pingone.com/\(pingConfig.environmentId)/as/.well-known/openid-configuration"
                oidcValue.acrValues = pingConfig.registrationPolicyId
                oidcValue.additionalParameters = ["prompt": "login"]
            }
            daVinciConfig.module(ProtectLifecycleModule.config) { protectValue in
                protectValue.isBehavioralDataCollection = true
                protectValue.isLazyMetadata = true
                protectValue.envId = pingConfig.environmentId
                protectValue.isConsoleLogEnabled = true
                protectValue.pauseBehavioralDataOnSuccess = true
                protectValue.resumeBehavioralDataOnStart = true
            }
        }
        Task {
            await startFlow()
        }
    }

    func startFlow() async {
        isLoading = true
        errorMessage = nil
        isComplete = false
        let node = await daVinci.start()
        await handleNode(node)
    }

    func next(_ node: ContinueNode) async {
        isLoading = true
        errorMessage = nil
        let nextNode = await node.next()
        await handleNode(nextNode)
    }

    private func handleNode(_ node: Node) async {
        switch node {
        case let continueNode as ContinueNode:
            // Check for inline token success (registration complete)
            if continueNode.input["access_token"] != nil {
                await MainActor.run {
                    self.isComplete = true
                    self.isLoading = false
                }
                return
            }
            // Check for empty collectors with success indicator
            if continueNode.collectors.isEmpty {
                let capabilityName = continueNode.input["capabilityName"] as? String ?? ""
                if capabilityName.contains("Success") || capabilityName.contains("success") {
                    await MainActor.run {
                        self.isComplete = true
                        self.isLoading = false
                    }
                    return
                }
            }
            await MainActor.run {
                self.state = DavinciState(node: continueNode)
                self.isLoading = false
            }

        case is SuccessNode:
            await MainActor.run {
                self.isComplete = true
                self.isLoading = false
            }

        case let errorNode as ErrorNode:
            await MainActor.run {
                self.errorMessage = errorNode.message
                if let fallback = errorNode.continueNode {
                    self.state = DavinciState(node: fallback)
                }
                self.isLoading = false
            }

        case let failureNode as FailureNode:
            // Check for token-based success in FailureNode
            if let apiError = failureNode.cause as? ApiError {
                switch apiError {
                case .error(_, let json, _):
                    if json["access_token"] != nil {
                        await MainActor.run {
                            self.isComplete = true
                            self.isLoading = false
                        }
                        return
                    }
                }
            }
            // Check for localhost/empty URL error — treat as needing to restart current step
            let errorDesc = failureNode.cause.localizedDescription
            if errorDesc.contains("localhost") || errorDesc.contains("Could not connect to the server") {
                await MainActor.run {
                    self.errorMessage = "Please check your input and try again."
                    self.isLoading = false
                }
                return
            }
            await MainActor.run {
                self.errorMessage = "Unable to connect. Please try again."
                self.isLoading = false
            }

        default:
            await MainActor.run {
                self.errorMessage = "Unexpected response"
                self.isLoading = false
            }
        }
    }
}

// MARK: - RegistrationView

struct RegistrationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RegistrationViewModel()

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    BrandHeader()

                    if viewModel.isComplete {
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
                    } else if viewModel.isLoading {
                        ProgressView("Connecting...")
                            .padding(.top, 40)
                    } else {
                        switch viewModel.state.node {
                        case let continueNode as ContinueNode:
                            RegistrationContinueNodeView(viewModel: viewModel, node: continueNode)
                        case is SuccessNode:
                            ProgressView("Completing...")
                        case let errorNode as ErrorNode:
                            Text(errorNode.message)
                                .foregroundColor(.red)
                                .padding()
                        case is FailureNode:
                            Text("Connection failed")
                                .foregroundColor(.red)
                        default:
                            Text("Waiting...")
                                .foregroundColor(.secondary)
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Try Again") {
                            Task { await viewModel.startFlow() }
                        }
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(CustomerConfig.current.primaryColor)
                    }

                    if !viewModel.isComplete {
                        Button("Back to Sign In") {
                            dismiss()
                        }
                        .font(.callout)
                        .foregroundColor(CustomerConfig.current.primaryColor)
                        .padding(.top, 8)
                    }
                }
                .padding(.top, 40)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - RegistrationContinueNodeView

struct RegistrationContinueNodeView: View {
    let viewModel: RegistrationViewModel
    let node: ContinueNode

    private var hasOnlyProtectCollectors: Bool {
        let visibleCollectors = node.collectors.filter {
            $0 is TextCollector || $0 is PasswordCollector || $0 is SubmitCollector ||
            $0 is FlowCollector || $0 is SingleSelectCollector
        }
        return visibleCollectors.isEmpty && node.collectors.contains(where: { $0 is ProtectCollector })
    }

    var body: some View {
        VStack(spacing: 16) {
            if hasOnlyProtectCollectors {
                ProgressView("Verifying device...")
                    .onAppear {
                        Task {
                            for collector in node.collectors {
                                if let protect = collector as? ProtectCollector {
                                    let _ = await protect.collect()
                                }
                            }
                            await viewModel.next(node)
                        }
                    }
            } else if node.collectors.isEmpty {
                NodeMessageView(node: node) {
                    Task { await viewModel.next(node) }
                }
            } else {
                ForEach(node.collectors, id: \.id) { collector in
                    switch collector {
                    case let text as TextCollector:
                        TextField(text.label, text: Binding(
                            get: { text.value },
                            set: { text.value = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(.horizontal)

                    case let pass as PasswordCollector:
                        SecureField(pass.label, text: Binding(
                            get: { pass.value },
                            set: { pass.value = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)

                    case let singleSelect as SingleSelectCollector:
                        SingleSelectField(collector: singleSelect)
                            .padding(.horizontal)

                    case let protect as ProtectCollector:
                        EmptyView()
                            .onAppear {
                                Task {
                                    let _ = await protect.collect()
                                }
                            }

                    case let submit as SubmitCollector:
                        PingButton(title: submit.label.isEmpty ? "Continue" : submit.label) {
                            Task { await viewModel.next(node) }
                        }
                        .padding(.horizontal)

                    case let flow as FlowCollector:
                        Button(flow.label) {
                            Task { await viewModel.next(node) }
                        }
                        .font(.callout)
                        .foregroundColor(CustomerConfig.current.primaryColor)

                    default:
                        EmptyView()
                    }
                }

                if !node.collectors.contains(where: { $0 is SubmitCollector }) {
                    PingButton(title: "Continue") {
                        Task { await viewModel.next(node) }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - NodeMessageView (shared: customHtmlMessage handler)

struct NodeMessageView: View {
    let node: ContinueNode
    let onContinue: () -> Void
    private let config = CustomerConfig.current

    private var messageTitle: String {
        if let screen = node.input["screen"] as? [String: Any],
           let properties = screen["properties"] as? [String: Any],
           let messageTitleObj = properties["messageTitle"] as? [String: Any],
           let value = messageTitleObj["value"] as? String {
            return value
        }
        // Fallback: try node name/description
        if !node.name.isEmpty { return node.name }
        if !node.description.isEmpty { return node.description }
        return "Please review and continue"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.orange)

            Text(messageTitle)
                .font(.callout)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)

            PingButton(title: "Continue") {
                onContinue()
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    NavigationStack {
        RegistrationView()
    }
}
