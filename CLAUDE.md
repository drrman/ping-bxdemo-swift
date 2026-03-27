# CLAUDE.md

## Project Overview
Swift/SwiftUI demo app for Ping Identity CIAM authentication using the PingDavinci SDK.

## Build & Run
```
xcodebuild -project ping-bxdemo-swift.xcodeproj -scheme ping-bxdemo-swift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
iOS 16+ deployment target. SPM dependency: `ping-ios-sdk` v1.3.1 from `https://github.com/ForgeRock/ping-ios-sdk`.

## Working Configuration
- **DaVinci Login Policy ID:** `5a28929c0728d0cdc3c11db210afb9b5`
- **PingOne Client ID:** `26083e6f-d1ce-4fc4-9b74-e777b29d3687`
- **Environment ID:** `0cd2fe5b-cbfa-4164-a1cd-fab99a27bf92`
- **Redirect URI:** `bxdemo://callback` (custom URL scheme registered in Info.plist)
- **Discovery Endpoint:** `https://auth.pingone.com/{environmentId}/as/.well-known/openid-configuration`

## Auth Pattern
- DaVinci flow uses `returnSuccessResponseWidget` capability — tokens are returned inline in the Connector node's `input` dictionary (not via a separate `authorizeResponse` key).
- The SDK returns a `ContinueNode` (Connector subclass) with 0 collectors and `access_token`, `id_token`, `refresh_token` directly in `input`.
- LoginViewModel checks for `input["access_token"]` on ContinueNode before checking collectors — this is the primary auth completion path.
- The SDK's standard `SuccessNode` path (via `authorizeResponse`) is also handled but not triggered by the current DaVinci flow config.
- FailureNode fallback handles `flowResponseUrl` (redirect-based success) and direct token extraction.

## SwiftUI Integration Pattern
- ViewModel uses `@MainActor class LoginViewModel: ObservableObject` with `@Published var state: DavinciState` (wrapper class around `Node?`).
- Every state update creates a new `DavinciState` instance to force `objectWillChange`.
- View switches on `viewModel.state.node` to render ContinueNode/SuccessNode/ErrorNode.
- Pattern matches the SDK's own sample app in `SampleApps/PingExample/`.

## Key Files
- `Config/PingConfig.swift` — All Ping environment/policy IDs
- `Config/CustomerConfig.swift` — Branding, colors, content tiles (Southwest Airlines default)
- `Views/LoginView.swift` — DaVinci login flow + LoginViewModel + LoginContinueNodeView
- `Views/HomeView.swift` — Post-auth landing with TabView (Home + Profile)
- `Views/ProfileView.swift` — JWT claims display from id_token
- `Views/RegistrationView.swift` — Standalone registration flow
- `Views/StepUpView.swift` — Step-up auth modal
- `Services/AuthService.swift` — Keychain token storage + JWT decoding
- `Components/DaVinciFormView.swift` — SDK collector rendering (used by registration/step-up)
- `Components/ManualFormView.swift` — Fallback form for raw PingOne responses

## Adding New Files
New .swift files must be added to `project.pbxproj` manually (PBXFileReference + PBXBuildFile + group membership + Sources build phase).
