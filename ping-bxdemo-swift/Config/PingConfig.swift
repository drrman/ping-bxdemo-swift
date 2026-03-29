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
        environmentId: "0cd2fe5b-cbfa-4164-a1cd-fab99a27bf92",
        clientId: "26083e6f-d1ce-4fc4-9b74-e777b29d3687",
        loginPolicyId: "5a28929c0728d0cdc3c11db210afb9b5",
        registrationPolicyId: "407356ac7bf4f1e88c627d63a3735a7e",
        stepUpPolicyId: "",
        oidcPolicyId: "",
        redirectUri: "bxdemo://callback",
        scopes: ["openid", "profile", "email"]
    )
}
