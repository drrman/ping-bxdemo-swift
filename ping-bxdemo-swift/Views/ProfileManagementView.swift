import SwiftUI

struct ProfileManagementView: View {
    @EnvironmentObject private var authService: AuthService
    private let config = CustomerConfig.current
    private let pingConfig = PingConfig.current

    // Edit Profile
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var userId: String = ""
    @State private var isLoadingProfile = true
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    // Change Password
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isChangingPassword = false
    @State private var passwordMessage: String?
    @State private var passwordIsError = false

    // MFA Devices
    @State private var devices: [MFADevice] = []
    @State private var isLoadingDevices = true
    @State private var showRemoveAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Profile Header
                ZStack {
                    Circle()
                        .fill(config.primaryColor)
                        .frame(width: 80, height: 80)
                    Text(initials)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }

                if isLoadingProfile {
                    ProgressView("Loading profile...")
                } else {
                    // MARK: - Edit Profile Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Edit Profile")
                            .font(.headline)

                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("First Name").font(.caption).foregroundColor(.secondary)
                                TextField("First Name", text: $firstName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Last Name").font(.caption).foregroundColor(.secondary)
                                TextField("Last Name", text: $lastName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Email").font(.caption).foregroundColor(.secondary)
                                Text(email)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color(.tertiarySystemBackground))
                                    .cornerRadius(6)
                            }
                        }

                        PingButton(title: isSaving ? "Saving..." : "Save Changes") {
                            Task { await saveProfile() }
                        }

                        if let message = statusMessage {
                            Text(message)
                                .font(.callout)
                                .foregroundColor(statusIsError ? .red : .green)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // MARK: - Change Password Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Change Password")
                            .font(.headline)

                        VStack(spacing: 12) {
                            SecureField("Current Password", text: $currentPassword)
                                .textFieldStyle(.roundedBorder)

                            SecureField("New Password", text: $newPassword)
                                .textFieldStyle(.roundedBorder)

                            SecureField("Confirm New Password", text: $confirmPassword)
                                .textFieldStyle(.roundedBorder)
                        }

                        if !confirmPassword.isEmpty && newPassword != confirmPassword {
                            Text("Passwords do not match")
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        PingButton(title: isChangingPassword ? "Updating..." : "Update Password") {
                            Task { await changePassword() }
                        }

                        if let message = passwordMessage {
                            Text(message)
                                .font(.callout)
                                .foregroundColor(passwordIsError ? .red : .green)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // MARK: - MFA Devices Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("MFA Devices")
                            .font(.headline)

                        if isLoadingDevices {
                            ProgressView("Loading devices...")
                                .frame(maxWidth: .infinity)
                        } else if devices.isEmpty {
                            Text("No MFA devices enrolled")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(devices) { device in
                                    HStack(spacing: 12) {
                                        Image(systemName: device.iconName)
                                            .font(.title3)
                                            .foregroundColor(config.primaryColor)
                                            .frame(width: 32)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(device.typeLabel)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            if let detail = device.detail {
                                                Text(detail)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        Spacer()

                                        Button("Remove") {
                                            showRemoveAlert = true
                                        }
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    }
                                    .padding(.vertical, 10)

                                    if device.id != devices.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // MARK: - Account Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Account")
                            .font(.headline)

                        Button {
                            authService.clearTokens()
                        } label: {
                            Text("Sign Out")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Manage Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProfile()
            await loadDevices()
        }
        .alert("Remove Device", isPresented: $showRemoveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Contact your admin to remove MFA devices.")
        }
    }

    // MARK: - Helpers

    private var initials: String {
        let parts = [firstName, lastName].filter { !$0.isEmpty }
        return parts.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private var apiBase: String {
        "https://api.pingone.com/v1/environments/\(pingConfig.environmentId)/users/\(userId)"
    }

    // MARK: - Load Profile

    private func loadProfile() async {
        guard let claims = AuthService.shared.getUserFromToken() else {
            isLoadingProfile = false
            return
        }

        firstName = claims["given_name"] as? String ?? ""
        lastName = claims["family_name"] as? String ?? ""
        email = claims["email"] as? String ?? ""
        userId = claims["sub"] as? String ?? ""

        guard !userId.isEmpty, let accessToken = AuthService.shared.getStoredAccessToken() else {
            isLoadingProfile = false
            return
        }

        guard let url = URL(string: apiBase) else {
            isLoadingProfile = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let (data, response) = try? await URLSession.shared.data(for: request),
           let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let name = json["name"] as? [String: Any] {
                firstName = name["given"] as? String ?? firstName
                lastName = name["family"] as? String ?? lastName
            }
            email = json["email"] as? String ?? email
        }

        isLoadingProfile = false
    }

    // MARK: - Save Profile

    private func saveProfile() async {
        guard !userId.isEmpty, let accessToken = AuthService.shared.getStoredAccessToken() else {
            statusMessage = "Unable to save — not authenticated"
            statusIsError = true
            return
        }

        isSaving = true
        statusMessage = nil

        guard let url = URL(string: apiBase) else {
            isSaving = false
            statusMessage = "Invalid API endpoint"
            statusIsError = true
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": [
                "given": firstName,
                "family": lastName,
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse

            if httpResponse?.statusCode == 200 {
                statusMessage = "Profile updated successfully"
                statusIsError = false
            } else {
                let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let message = errorJson?["message"] as? String ?? "Update failed (status \(httpResponse?.statusCode ?? 0))"
                statusMessage = message
                statusIsError = true
            }
        } catch {
            statusMessage = "Connection error: \(error.localizedDescription)"
            statusIsError = true
        }

        isSaving = false
    }

    // MARK: - Change Password

    private func changePassword() async {
        guard !currentPassword.isEmpty else {
            passwordMessage = "Enter your current password"
            passwordIsError = true
            return
        }
        guard !newPassword.isEmpty else {
            passwordMessage = "Enter a new password"
            passwordIsError = true
            return
        }
        guard newPassword == confirmPassword else {
            passwordMessage = "Passwords do not match"
            passwordIsError = true
            return
        }
        guard !userId.isEmpty, let accessToken = AuthService.shared.getStoredAccessToken() else {
            passwordMessage = "Not authenticated"
            passwordIsError = true
            return
        }

        isChangingPassword = true
        passwordMessage = nil

        guard let url = URL(string: "\(apiBase)/password") else {
            isChangingPassword = false
            passwordMessage = "Invalid API endpoint"
            passwordIsError = true
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.pingidentity.password.reset+json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "currentPassword": currentPassword,
            "newPassword": newPassword,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse

            if httpResponse?.statusCode == 200 {
                passwordMessage = "Password updated successfully"
                passwordIsError = false
                currentPassword = ""
                newPassword = ""
                confirmPassword = ""
            } else {
                let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let message = errorJson?["message"] as? String ?? "Password update failed (status \(httpResponse?.statusCode ?? 0))"
                passwordMessage = message
                passwordIsError = true
            }
        } catch {
            passwordMessage = "Connection error: \(error.localizedDescription)"
            passwordIsError = true
        }

        isChangingPassword = false
    }

    // MARK: - Load MFA Devices

    private func loadDevices() async {
        guard !userId.isEmpty, let accessToken = AuthService.shared.getStoredAccessToken() else {
            isLoadingDevices = false
            return
        }

        guard let url = URL(string: "\(apiBase)/devices") else {
            isLoadingDevices = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse

            if httpResponse?.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let embedded = json["_embedded"] as? [String: Any],
               let deviceArray = embedded["devices"] as? [[String: Any]] {
                devices = deviceArray.compactMap { MFADevice(from: $0) }
            }
        } catch {
            // Silently fail — show empty list
        }

        isLoadingDevices = false
    }
}

// MARK: - MFA Device Model

struct MFADevice: Identifiable {
    let id: String
    let type: String
    let detail: String?

    var typeLabel: String {
        switch type.uppercased() {
        case "SMS": return "SMS"
        case "EMAIL": return "Email"
        case "TOTP": return "Authenticator App"
        case "MOBILE": return "Mobile App"
        default: return type
        }
    }

    var iconName: String {
        switch type.uppercased() {
        case "SMS": return "phone.fill"
        case "EMAIL": return "envelope.fill"
        case "TOTP": return "shield.fill"
        case "MOBILE": return "iphone"
        default: return "shield.fill"
        }
    }

    init?(from json: [String: Any]) {
        guard let id = json["id"] as? String,
              let type = json["type"] as? String else { return nil }
        self.id = id
        self.type = type
        self.detail = json["phone"] as? String
            ?? json["email"] as? String
            ?? json["nickname"] as? String
    }
}

#Preview {
    NavigationStack {
        ProfileManagementView()
            .environmentObject(AuthService.shared)
    }
}
