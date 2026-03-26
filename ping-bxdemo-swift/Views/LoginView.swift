import SwiftUI
import PingDavinci
import PingOidc
import PingOrchestrate

@MainActor
class LoginViewModel: ObservableObject {
    @Published var currentNode: Node?
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var isAuthenticated = false

    private let daVinci: DaVinci
    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
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

        case let successNode as SuccessNode:
            if let user = successNode.user {
                let tokenResult = await user.token()
                switch tokenResult {
                case .success(let token):
                    authService.storeTokens(
                        accessToken: token.accessToken,
                        idToken: token.idToken,
                        refreshToken: token.refreshToken
                    )
                    self.isAuthenticated = true
                case .failure(let error):
                    self.errorMessage = "Token error: \(error.localizedDescription)"
                }
            } else {
                self.isAuthenticated = true
            }

        case let errorNode as ErrorNode:
            self.errorMessage = errorNode.message
            self.currentNode = errorNode.continueNode

        case let failureNode as FailureNode:
            self.errorMessage = "Authentication failed: \(failureNode.cause.localizedDescription)"
            // Restart the flow on failure
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

struct LoginView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var viewModel: LoginViewModel

    init(authService: AuthService = .shared) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(authService: authService))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    BrandHeader()

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
                }
                .padding(.top, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationDestination(isPresented: $viewModel.isAuthenticated) {
                HomeView()
                    .environmentObject(authService)
                    .navigationBarBackButtonHidden(true)
            }
        }
        .task {
            await viewModel.startFlow()
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService.shared)
}
