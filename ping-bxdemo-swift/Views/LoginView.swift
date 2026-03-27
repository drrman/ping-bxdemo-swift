import SwiftUI
import PingDavinci
import PingOidc
import PingOrchestrate
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

    private let daVinci: DaVinci
    private let authService: AuthService

    init() {
        self.authService = AuthService.shared
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
        Task {
            await startFlow()
        }
    }

    func startFlow() async {
        isLoading = true
        errorMessage = nil
        useFallbackForm = false
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
            await MainActor.run {
                self.errorMessage = errorNode.message
                if let fallback = errorNode.continueNode {
                    self.state = DavinciState(node: fallback)
                }
                self.isLoading = false
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

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    BrandHeader()

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
                }
                .padding(.top, 40)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

// MARK: - LoginContinueNodeView

struct LoginContinueNodeView: View {
    let viewModel: LoginViewModel
    let node: ContinueNode

    var body: some View {
        VStack(spacing: 16) {
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
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService.shared)
}
