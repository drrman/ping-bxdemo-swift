import Foundation

struct PingConfig {
    let environmentId: String
    let clientId: String
    let loginPolicyId: String
    let registrationPolicyId: String
    let stepUpPolicyId: String
    let oidcPolicyId: String
    let redirectUri: String
    let scopes: [String]

    static let current = PingConfig(
        environmentId: "e08cdcdf-2389-418f-9064-aaa9ee4c5150",
        clientId: "78427c21-993e-4852-a05b-72e0139a41a2",
        loginPolicyId: "56f1907ce63e06dc0e9493ff1b72ba8e",
        registrationPolicyId: "01292a062d3e2960d2953f92849c6c17",
        stepUpPolicyId: "9c312501435e0e4875de485b50d0ff58",
        oidcPolicyId: "",
        redirectUri: "bxdemo://callback",
        scopes: ["openid", "profile", "email"]
    )
}
