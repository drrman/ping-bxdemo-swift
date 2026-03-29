import SwiftUI
import AuthenticationServices
import PingDavinci
import PingOidc
import PingOrchestrate
import PingProtect
import CryptoKit

// MARK: - DaVinci State Wrapper (from SDK sample pattern)

class DavinciState {
    var node: Node? = nil
    init(node: Node? = nil) {
        self.node = node
    }
}

// MARK: - Redirect Capture Delegate

class RedirectCapture: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Don't follow redirect — capture it instead
    }
}

// MARK: - LoginViewModel

@MainActor
class LoginViewModel: ObservableObject {
    @Published var state: DavinciState = DavinciState()
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil

    // Fallback mode
    @Published var useFallbackForm = false
    @Published var fallbackFields: [ManualFormField] = []
    private var fallbackCheckHref: String?
    private var fallbackResumeUrl: String?
    private var fallbackCookies: [HTTPCookie] = []

    private var daVinci: DaVinci
    private let authService: AuthService

    private static func createFreshDaVinci() -> DaVinci {
        let pingConfig = PingConfig.current
        return DaVinci.createDaVinci { daVinciConfig in
            daVinciConfig.module(PingDavinci.OidcModule.config) { oidcValue in
                oidcValue.clientId = pingConfig.clientId
                oidcValue.scopes = Set(pingConfig.scopes)
                oidcValue.redirectUri = pingConfig.redirectUri
                oidcValue.discoveryEndpoint = "https://auth.pingone.com/\(pingConfig.environmentId)/as/.well-known/openid-configuration"
                oidcValue.acrValues = pingConfig.loginPolicyId
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
    }

    init() {
        self.authService = AuthService.shared
        self.daVinci = Self.createFreshDaVinci()
        if CustomerConfig.current.authMode == .davinci {
            Task {
                await startFlow()
            }
        } else {
            self.isLoading = false
        }
    }

    func startFlow() async {
        isLoading = true
        errorMessage = nil
        useFallbackForm = false
        // Invalidate any existing server-side session before starting fresh
        let signoffURL = URL(string: "https://auth.pingone.com/\(PingConfig.current.environmentId)/as/signoff")!
        var signoffRequest = URLRequest(url: signoffURL)
        signoffRequest.httpMethod = "GET"
        _ = try? await URLSession.shared.data(for: signoffRequest)
        // Clear all cached cookies to prevent stale session from previous flow
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        URLCache.shared.removeAllCachedResponses()
        // Create fresh DaVinci instance
        self.daVinci = Self.createFreshDaVinci()
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
        print("[LoginVM] handleNode: \(type(of: node))")
        switch node {
        case let continueNode as ContinueNode:
            let collectors = continueNode.collectors
            let inputKeys = Array(continueNode.input.keys).sorted()
            print("[LoginVM] ContinueNode — collectors: \(collectors.count), input keys: \(inputKeys)")

            // Check for tokens directly in the response (returnSuccessResponseWidget)
            if let accessToken = continueNode.input["access_token"] as? String {
                print("[LoginVM] Found access_token in ContinueNode input — completing auth")
                await MainActor.run {
                    self.authService.storeTokens(
                        accessToken: accessToken,
                        idToken: continueNode.input["id_token"] as? String,
                        refreshToken: continueNode.input["refresh_token"] as? String
                    )
                    self.isLoading = false
                }
                return
            }

            if collectors.isEmpty {
                if let status = continueNode.input["status"] as? String, status == "USERNAME_PASSWORD_REQUIRED" {
                    activateFallback(from: continueNode.input)
                    await MainActor.run {
                        self.isLoading = false
                    }
                    return
                }
                // Log unhandled empty-collector case
                print("[LoginVM] ContinueNode with 0 collectors, capabilityName: \(continueNode.input["capabilityName"] ?? "nil")")
            }
            await MainActor.run {
                self.state = DavinciState(node: continueNode)
                self.isLoading = false
            }

        case let successNode as SuccessNode:
            print("[LoginVM] SuccessNode — user: \(successNode.user != nil ? "present" : "nil")")
            if let user = successNode.user {
                let tokenResult = await user.token()
                switch tokenResult {
                case .success(let token):
                    print("[LoginVM] Token via SDK — accessToken length: \(token.accessToken.count)")
                    await MainActor.run {
                        self.authService.storeTokens(
                            accessToken: token.accessToken,
                            idToken: token.idToken,
                            refreshToken: token.refreshToken
                        )
                        self.isLoading = false
                    }
                case .failure(let error):
                    print("[LoginVM] Token error: \(error)")
                    await MainActor.run {
                        self.errorMessage = "Token error: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                }
            } else {
                // Check if tokens are in the input directly
                if let accessToken = successNode.input["access_token"] as? String {
                    print("[LoginVM] Found access_token in SuccessNode input")
                    await MainActor.run {
                        self.authService.storeTokens(
                            accessToken: accessToken,
                            idToken: successNode.input["id_token"] as? String,
                            refreshToken: successNode.input["refresh_token"] as? String
                        )
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.authService.isAuthenticated = true
                        self.isLoading = false
                    }
                }
            }

        case let errorNode as ErrorNode:
            print("[LoginVM] ErrorNode — message: \(errorNode.message)")
            if let continueNode = errorNode.continueNode {
                print("[LoginVM] ErrorNode has continueNode — advancing flow instead of showing error")
                await handleNode(continueNode)
            } else {
                await MainActor.run {
                    self.errorMessage = errorNode.message
                    self.isLoading = false
                }
            }

        case let failureNode as FailureNode:
            print("[LoginVM] FailureNode — cause: \(failureNode.cause)")
            // Check if this contains tokens or a flowResponseUrl
            if let apiError = failureNode.cause as? ApiError {
                switch apiError {
                case .error(let status, let json, let message):
                    print("[LoginVM] FailureNode ApiError — status: \(status), keys: \(Array(json.keys).sorted()), message: \(message)")

                    // Check for tokens directly in the failure response
                    if let accessToken = json["access_token"] as? String {
                        print("[LoginVM] Found access_token in FailureNode — completing auth")
                        await MainActor.run {
                            self.authService.storeTokens(
                                accessToken: accessToken,
                                idToken: json["id_token"] as? String,
                                refreshToken: json["refresh_token"] as? String
                            )
                            self.isLoading = false
                        }
                        return
                    }

                    // Check for flowResponseUrl (redirect-based success)
                    if let flowResponseUrl = json["flowResponseUrl"] as? String {
                        await handleFlowResponseUrl(flowResponseUrl, from: json)
                        return
                    }
                }
            }
            // Check for localhost/empty URL error
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
            print("[LoginVM] Unknown node: \(type(of: node))")
            await MainActor.run {
                self.errorMessage = "Unexpected response"
                self.isLoading = false
            }
        }
    }

    // MARK: - FlowResponseUrl Handling (redirect-based success)

    private func handleFlowResponseUrl(_ flowResponseUrl: String, from json: [String: Any]) async {
        guard let url = URL(string: flowResponseUrl) else {
            await MainActor.run {
                self.errorMessage = "Invalid flow response URL"
                self.isLoading = false
            }
            return
        }

        do {
            // Step 1: GET the flowResponseUrl — capture the redirect, don't follow it
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            // Inject cookies from the shared cookie storage (SDK manages these)
            if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
                let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
                for (key, value) in cookieHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            let config = URLSessionConfiguration.default
            config.httpShouldSetCookies = true
            config.httpCookieAcceptPolicy = .always
            let redirectCapture = RedirectCapture()
            let session = URLSession(configuration: config, delegate: redirectCapture, delegateQueue: nil)

            let (_, response) = try await session.data(for: request)
            let httpResponse = response as? HTTPURLResponse

            // Step 2: Extract the authorization code from the Location header
            guard let locationHeader = httpResponse?.value(forHTTPHeaderField: "Location"),
                  let locationUrl = URL(string: locationHeader),
                  let components = URLComponents(url: locationUrl, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                // Try the final URL if no Location header
                if let finalUrl = httpResponse?.url,
                   let components = URLComponents(url: finalUrl, resolvingAgainstBaseURL: false),
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                    await exchangeCodeForTokens(code: code, codeVerifier: nil)
                    return
                }
                await MainActor.run {
                    self.errorMessage = "Could not extract authorization code"
                    self.isLoading = false
                }
                return
            }

            // Step 3: Exchange code for tokens
            await exchangeCodeForTokens(code: code, codeVerifier: nil)

        } catch {
            await MainActor.run {
                self.errorMessage = "Flow completion error: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func exchangeCodeForTokens(code: String, codeVerifier: String?) async {
        let pingConfig = PingConfig.current
        guard let url = URL(string: "https://auth.pingone.com/\(pingConfig.environmentId)/as/token") else {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Invalid token endpoint"
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params = [
            "grant_type=authorization_code",
            "code=\(code)",
            "client_id=\(pingConfig.clientId)",
            "redirect_uri=\(pingConfig.redirectUri)",
        ]
        if let codeVerifier = codeVerifier {
            params.append("code_verifier=\(codeVerifier)")
        }
        request.httpBody = params.joined(separator: "&").data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessToken = json["access_token"] as? String {
                await MainActor.run {
                    self.authService.storeTokens(
                        accessToken: accessToken,
                        idToken: json["id_token"] as? String,
                        refreshToken: json["refresh_token"] as? String
                    )
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Token exchange failed"
                }
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Token exchange error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Fallback (raw PingOne response)

    private func activateFallback(from input: [String: Any]) {
        if let links = input["_links"] as? [String: Any],
           let check = links["usernamePassword.check"] as? [String: Any],
           let href = check["href"] as? String {
            fallbackCheckHref = href
        }
        if let resumeUrl = input["resumeUrl"] as? String {
            fallbackResumeUrl = resumeUrl
        }
        fallbackFields = [
            ManualFormField(key: "username", label: "Email Address", isPassword: false),
            ManualFormField(key: "password", label: "Password", isPassword: true),
        ]
        useFallbackForm = true
        state = DavinciState()
        errorMessage = nil
    }

    func submitFallback(values: [String: String]) async {
        guard let checkHref = fallbackCheckHref else {
            errorMessage = "No authentication endpoint available"
            return
        }
        let username = values["username"] ?? ""
        let password = values["password"] ?? ""
        guard !username.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter your email and password"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let checkResult = try await postCredentials(url: checkHref, username: username, password: password)
            if let responseBody = checkResult.body {
                let status = responseBody["status"] as? String ?? ""
                if status == "FAILED" {
                    let detail = (responseBody["details"] as? [[String: Any]])?.first
                    let message = detail?["userMessage"] as? String
                        ?? detail?["message"] as? String
                        ?? "Invalid username or password"
                    isLoading = false
                    errorMessage = message
                    return
                }
                let resumeUrl = responseBody["resumeUrl"] as? String ?? fallbackResumeUrl
                if status == "COMPLETED", let resumeUrl = resumeUrl {
                    try await followResumeUrl(resumeUrl)
                    return
                }
                if responseBody["authorizeResponse"] != nil {
                    try await followResumeUrl(checkHref)
                    return
                }
                if responseBody["_links"] is [String: Any] {
                    isLoading = false
                    errorMessage = "Additional verification required (status: \(status))."
                    return
                }
            }
            if let redirectUrl = checkResult.redirectUrl {
                try await followResumeUrl(redirectUrl)
                return
            }
            isLoading = false
            errorMessage = "Unexpected response from authentication server"
        } catch {
            isLoading = false
            errorMessage = "Connection error: \(error.localizedDescription)"
        }
    }

    private struct HTTPResult {
        let statusCode: Int
        let body: [String: Any]?
        let redirectUrl: String?
        let cookies: [HTTPCookie]
    }

    private func postCredentials(url: String, username: String, password: String) async throws -> HTTPResult {
        guard let requestUrl = URL(string: url) else { throw URLError(.badURL) }
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "POST"
        request.setValue("application/vnd.pingidentity.usernamePassword.check+json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let cookieHeaders = HTTPCookie.requestHeaderFields(with: fallbackCookies)
        for (key, value) in cookieHeaders { request.setValue(value, forHTTPHeaderField: key) }
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        if let headerFields = httpResponse?.allHeaderFields as? [String: String],
           let responseUrl = httpResponse?.url {
            fallbackCookies.append(contentsOf: HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: responseUrl))
        }
        return HTTPResult(
            statusCode: httpResponse?.statusCode ?? 0,
            body: try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            redirectUrl: httpResponse?.value(forHTTPHeaderField: "Location"),
            cookies: fallbackCookies
        )
    }

    private func followResumeUrl(_ urlString: String) async throws {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let cookieHeaders = HTTPCookie.requestHeaderFields(with: fallbackCookies)
        for (key, value) in cookieHeaders { request.setValue(value, forHTTPHeaderField: key) }
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        let redirectCapture = RedirectCapture()
        let session = URLSession(configuration: config, delegate: redirectCapture, delegateQueue: nil)
        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        // Check Location header for redirect with code
        if let location = httpResponse?.value(forHTTPHeaderField: "Location"),
           let locationUrl = URL(string: location),
           let components = URLComponents(url: locationUrl, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            await exchangeCodeForTokens(code: code, codeVerifier: nil)
            return
        }
        // Check final URL for code
        if let finalUrl = httpResponse?.url,
           let components = URLComponents(url: finalUrl, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            await exchangeCodeForTokens(code: code, codeVerifier: nil)
            return
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let accessToken = json["access_token"] as? String {
            authService.storeTokens(
                accessToken: accessToken,
                idToken: json["id_token"] as? String,
                refreshToken: json["refresh_token"] as? String
            )
            return
        }
        isLoading = false
        errorMessage = "Could not complete authentication flow"
    }
}

// MARK: - LoginView

struct LoginView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var viewModel = LoginViewModel()
    @StateObject private var oidcService = OIDCAuthService()
    @State private var oidcError: String? = nil
    @State private var isOIDCLoading: Bool = false
    private let customerConfig = CustomerConfig.current

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    BrandHeader()

                    if customerConfig.authMode == .oidcRedirect {
                        VStack(spacing: 0) {
                            Spacer()

                            // Brand area
                            VStack(spacing: 16) {
                                // Try customer logo first, fall back to shield icon
                                if UIImage(named: customerConfig.logoAssetName) != nil {
                                    Image(customerConfig.logoAssetName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 80)
                                } else {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 64))
                                        .foregroundColor(customerConfig.primaryColor)
                                }

                                if !customerConfig.appName.isEmpty {
                                    Text(customerConfig.appName)
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text("BXDemo")
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                }

                                if !customerConfig.tagline.isEmpty {
                                    Text(customerConfig.tagline)
                                        .font(.subheadline)
                                        .foregroundColor(customerConfig.secondaryColor)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text("Secure identity powered by Ping Identity")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .padding(.horizontal, 32)

                            Spacer()
                            Spacer()

                            // Sign In button
                            Button(action: {
                                Task {
                                    isOIDCLoading = true
                                    oidcError = nil
                                    do {
                                        try await oidcService.startLogin(authService: authService)
                                    } catch ASWebAuthenticationSessionError.canceledLogin {
                                        // User cancelled — silent
                                    } catch {
                                        oidcError = error.localizedDescription
                                    }
                                    isOIDCLoading = false
                                }
                            }) {
                                if isOIDCLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(customerConfig.buttonBgColor)
                                        .cornerRadius(10)
                                } else {
                                    Text("Sign In")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(customerConfig.buttonBgColor)
                                        .foregroundColor(customerConfig.buttonColor)
                                        .cornerRadius(10)
                                        .fontWeight(.semibold)
                                }
                            }
                            .padding(.horizontal, 32)

                            if let error = oidcError {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                    .padding(.top, 8)
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // DaVinci mode — existing headless flow
                        if viewModel.isLoading {
                            ProgressView("Connecting...")
                                .padding(.top, 40)
                        } else if viewModel.useFallbackForm {
                            ManualFormView(
                                fields: viewModel.fallbackFields,
                                submitLabel: "Sign In"
                            ) { values in
                                Task { await viewModel.submitFallback(values: values) }
                            }
                            .padding(.horizontal)
                        } else {
                            switch viewModel.state.node {
                            case let continueNode as ContinueNode:
                                LoginContinueNodeView(viewModel: viewModel, node: continueNode)
                            case is SuccessNode:
                                ProgressView("Signing in...")
                            case let errorNode as ErrorNode:
                                if errorNode.continueNode == nil {
                                    Text(errorNode.message)
                                        .foregroundColor(.red)
                                        .padding()
                                }
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
                    }
                }
                .padding(.top, 40)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .onAppear {
            if CustomerConfig.current.authMode == .davinci {
                Task { await viewModel.startFlow() }
            }
        }
    }
}

// MARK: - LoginContinueNodeView

struct LoginContinueNodeView: View {
    let viewModel: LoginViewModel
    let node: ContinueNode
    @State private var showRegistration = false

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
                // Protect-only node: collect signals and auto-advance
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
                        // Invisible — collect signals silently alongside other fields
                        EmptyView()
                            .onAppear {
                                Task {
                                    let _ = await protect.collect()
                                }
                            }

                    case let submit as SubmitCollector:
                        PingButton(title: submit.label.isEmpty ? "Sign In" : submit.label) {
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
                    PingButton(title: "Sign In") {
                        Task { await viewModel.next(node) }
                    }
                    .padding(.horizontal)
                }
            }

            if node.collectors.contains(where: { ($0 as? TextCollector)?.key == "username" }) {
                Button("Don't have an account? Create one") {
                    showRegistration = true
                }
                .font(.callout)
                .foregroundColor(CustomerConfig.current.primaryColor)
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showRegistration) {
            RegistrationView()
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService.shared)
}
