# Ping Identity BXDEMO Swift — Full Project Handoff
> Paste this at the start of a new Claude chat to resume instantly.

---

## How Dustin and Claude Work Together

- **Dustin uses Claude Code** for all Swift code changes: `cd ~/Documents/ping-bxdemo-swift && claude --dangerously-skip-permissions`
- **Dustin pastes Claude Code prompts** from this chat into his terminal — Claude (this chat) writes the prompts, Claude Code executes them
- **Dustin pastes build results and Xcode logs** back into this chat for debugging
- **Dustin pastes DaVinci node logs** (JSON) when flow issues occur
- Claude diagnoses issues, writes the next Claude Code prompt, and Dustin runs it
- This cycle repeats — Claude is the architect/debugger, Claude Code is the implementer
- When DaVinci changes are needed, Claude gives step-by-step instructions for the DaVinci console UI
- Screenshots of the simulator, DaVinci flows, and PingOne console are pasted here for diagnosis

---

## Project Overview

Two repos that work together:

### Repo 1: ping-bxdemo-swift (IN PROGRESS — main active work)
Native SwiftUI iOS demo app for Ping Identity Sales Engineers.
Demonstrates CIAM capabilities using real PingOne + DaVinci.
Re-themeable per customer via CustomerConfig.swift.

**GitHub:** `dustin-rhodes_pingcorp/ping-bxdemo-swift`
**Local:** `~/Documents/ping-bxdemo-swift`
**Expo account:** N/A (this is pure Swift/Xcode, not React Native)

### Repo 2: ping-bxdemo-configurator (NOT STARTED)
React web app hosted on Netlify. Lets SEs configure the demo app per customer.
Point-and-click UI, no terminal needed. Full spec below.

---

## PingOne Environment Values

**PingConfig.swift (GITIGNORED — never commit)**
- environmentId: `0cd2fe5b-cbfa-4164-a1cd-fab99a27bf92`
- clientId: `26083e6f-d1ce-4fc4-9b74-e777b29d3687` (BXDEMO app)
- loginPolicyId: `5a28929c0728d0cdc3c11db210afb9b5`
- registrationPolicyId: `407356ac7bf4f1e88c627d63a3735a7e`
- redirectUri: `bxdemo://callback`
- scopes: `["openid", "profile", "email"]`
- stepUpPolicyId: `""` (not yet configured)

**DaVinci App (BXDEMO_Configurator):**
- App Client ID: `ee97055760c4c2aed20c458dd7137d56`
- API Key: stored locally only

**PingOne API base:** `https://api.pingone.com/v1/environments/0cd2fe5b-cbfa-4164-a1cd-fab99a27bf92`
**Auth base:** `https://auth.pingone.com/0cd2fe5b-cbfa-4164-a1cd-fab99a27bf92`
**SE admin email:** `drhodes@dbri.net`

---

## DaVinci Flows

### Login Flow (Headless-Login)
- flowId: `4071b3a4a3cc69c7dda7d1f576fffbb2`
- policyId: `5a28929c0728d0cdc3c11db210afb9b5`
- Nodes: Start Login (Custom HTML Template) → Find User (PingOne) → Check Password (PingOne) → Return Success Response (Widget Flows)
- Final node: **PingOne Authentication - Return Success Response (Widget Flows)**
- Returns tokens inline via `capabilityName: "returnSuccessResponseWidget"`

### Registration Flow (Headless-Registration)
- flowId: `631576b43975bca8cb1457a82d2ea629`
- policyId: `407356ac7bf4f1e88c627d63a3735a7e`
- Nodes: Enter Your Details → Enter Password → (Functions node removed — caused errors) → Find User → Create User → Email Verification (Send OTP) → Verify Email (Custom HTML Template, key: otp) → PingOne Validate Verification Code → **Http - Send Success JSON Response**
- Final node: **Http - Send Success JSON Response** (NOT returnSuccessResponseWidget — causes userSessionMismatch)
- Returns: `{"success": true, "registrationComplete": "true"}`
- CRITICAL: Verify Email node identifier must use UUID from Create User output, NOT email address

### Key DaVinci Lessons Learned
- `returnSuccessResponseWidget` = correct for login (issues tokens)
- `returnSuccessResponseWidget` causes `userSessionMismatch` for registration (use Http Send Success JSON instead)
- Functions connector: NO `return` statements — last expression is the output value
- Variables in Functions node accessed as `parameters.variableName` (from variableInputList)
- DaVinci Functions JS runs in isolated VM — standard JS but no `return`, no `parameters` global without variableInputList
- Verify Email (PingOne) requires UUID, not email address
- URL scheme: `bxdemo` registered in Xcode Info tab

---

## Authentication Architecture (WORKING)

### Critical Session Fix
Before starting a new login flow, call PingOne signoff to clear stale ST cookie:
```swift
let signoffURL = URL(string: "https://auth.pingone.com/\(PingConfig.current.environmentId)/as/signoff")!
var request = URLRequest(url: signoffURL)
request.httpMethod = "GET"
try? await URLSession.shared.data(for: request)
```
This prevents `userSessionMismatch` error when logging in after registration.

### SDK Pattern
- Uses **Ping DaVinci Swift SDK** (not REST calls like the React Native version)
- SDK handles PKCE, cookie management, token exchange automatically
- `DavinciState` wrapper class required to trigger SwiftUI re-renders:

```swift
class DavinciState {
    var node: Node? = nil
    init(node: Node? = nil) { self.node = node }
}

@MainActor
class LoginViewModel: ObservableObject {
    @Published var state: DavinciState = DavinciState()
    // Every update: self.state = DavinciState(node: next) — new instance forces re-render
}
```

### Token Extraction (Login)
DaVinci returns `capabilityName: "returnSuccessResponseWidget"` with tokens inline:
```swift
// In handleNode(), when ContinueNode has 0 collectors:
if input["access_token"] != nil {
    // extract access_token, id_token, refresh_token directly
    authService.storeTokens(...)
    authService.isAuthenticated = true
}
```

### Fresh DaVinci Instance
Create new DaVinci instance in `startFlow()` each time — never reuse:
```swift
func startFlow() async {
    // 1. Call signoff endpoint first
    // 2. Create fresh DaVinci instance
    // 3. await freshDaVinci.start()
}
```

---

## App Architecture

```
ping-bxdemo-swift/
  Config/
    CustomerConfig.swift    — branding (Southwest Airlines pre-populated)
    PingConfig.swift        — PingOne values (GITIGNORED)
  Views/
    LoginView.swift         — DaVinci SDK login, WORKING
    RegistrationView.swift  — DaVinci SDK registration, WORKING
    HomeView.swift          — post-auth landing with content tiles, WORKING
    ProfileView.swift       — JWT claims display + "Manage Profile" button, WORKING
    ProfileManagementView.swift — IN PROGRESS (native profile editing)
    StepUpView.swift        — modal step-up auth stub
  Components/
    BrandHeader.swift
    DaVinciFormView.swift   — dynamic collector renderer
    PingButton.swift
    PingTextField.swift
  Services/
    AuthService.swift       — Keychain token storage, isAuthenticated @Published
  Extensions/
    Color+Hex.swift
  Assets/
    Assets.xcassets/        — southwest-logo.png placeholder (logo not yet added)
```

### CustomerConfig.swift (Southwest Airlines)
```swift
export let customerConfig = CustomerConfig(
    appName: "Southwest Airlines",
    tagline: "Without a heart, it's just a machine.",
    primaryColor: "#304CB2",
    secondaryColor: "#FFBF27",
    buttonColor: "#FFFFFF",
    buttonBgColor: "#304CB2",
    footerBgColor: "#304CB2",
    homeBannerColor: "#FFBF27",
    logoAssetName: "southwest-logo",  // placeholder
    bannerAssetName: "southwest-banner",
    vertical: "airlines",
    customerSlug: "southwest-airlines",
    contentTiles: [
        ContentTile(title: "My Trips", subtitle: "View and manage your upcoming flights", icon: "airplane", action: .navigate),
        ContentTile(title: "Rapid Rewards", subtitle: "You have 24,500 points — redeem for your next trip", icon: "star.fill", action: .navigate),
        ContentTile(title: "Flight Deals", subtitle: "Exclusive member offers available now", icon: "tag.fill", action: .navigate),
        ContentTile(title: "Travel Documents", subtitle: "Passport and security", icon: "lock.shield.fill", action: .stepUp)
    ],
    stepUpTitle: "Verify Your Identity",
    stepUpSubtitle: "This section requires additional verification"
)
```

---

## What Is Complete ✅

1. **Login** — DaVinci SDK, PKCE, tokens stored in Keychain
2. **Login MFA** — Full MFA flow: check devices → existing users get SMS OTP → new users offered phone enrollment → verified phone saved to user profile
3. **Registration** — Multi-step: name/email → password → email OTP verification → success
4. **Login after registration** — signoff called first to clear stale session
5. **Home screen** — "Welcome back, Dustin", branded content tiles
6. **Profile screen** — JWT claims display (all token fields shown)
7. **Profile Management** — Native ProfileManagementView with 4 sections:
   - Edit Profile (PATCH PingOne Users API)
   - Change Password (PUT PingOne password API)
   - MFA Devices list (GET PingOne devices API, with type icons)
   - Sign Out (destructive, red button)
8. **Manage Profile button** — NavigationLink from ProfileView (native, no WebView)
9. **Sign Out** — calls PingOne /as/signoff, clears Keychain, nav resets to Login
10. **Dynamic form renderer** — renders whatever DaVinci returns (OTP, password, text fields, dropdowns)
11. **SingleSelectCollector (dropdown/radio)** — added to all three ContinueNodeViews (Login, Registration, DaVinciFormView)
12. **Southwest Airlines branding** — blue/gold, tagline, content tiles
13. **"Create Account" link** on LoginView → RegistrationView sheet

### MFA Enrollment Path (DaVinci)
Add Phone Number → Create Device → Verify Phone Number → Activate Device → Update User (saves mobilePhone) → Return Success

---

## What Is NOT Started Yet

### App Side
1. **Step-Up Auth** — needs stepUpPolicyId configured in DaVinci, then wire to StepUpView
2. **Logo asset** — add actual southwest-logo.png to Assets.xcassets
3. **UI polish** — branded PingTextField/PingButton on login/registration forms
4. **Remove debug print statements**
5. **Progressive profiling** — post-login profile enrichment flow

### Key DaVinci Lessons (MFA & Functions)
- Functions connector `parameters is not defined` when mapping HTTP node outputs directly → Fix: use **Flow Instance Variable** node to store value first, then map from Variables node output to Functions `variableInputList`
- `globalOutputs` and `flow.` prefixes do not work in Swift SDK context
- PingOne requires `mobilePhone` on user profile for Create Device Authentication One-Time Device mode
- Read All Devices returns `True` even with 0 devices → must use Functions node checking `rawResponse.size > 0`

---

## Configurator Tool Spec (Repo 2 — Full Spec)

### What It Is
Hosted React web app (Netlify) that lets SEs configure the demo app per customer.
Point-and-click — no terminal needed for the configuration step.

### SE Workflow
1. SE opens configurator in browser
2. Signs in with GitHub account (OAuth — all SEs in Ping Identity org)
3. Selects existing customer or creates new one
4. Fills out form: logo, colors, app name, PingOne values, DaVinci policy IDs
5. Sees live iPhone frame preview of all 5 screens updating in real time
6. Clicks Generate → configurator pushes CustomerConfig.swift + PingConfig.swift to GitHub branch via API
7. Sees Next Steps panel with copy-paste terminal commands

### Tech Stack
- Frontend: React + Vite + Tailwind CSS
- Hosting: Netlify
- Auth: GitHub OAuth App (Ping Identity org)
- GitHub Integration: GitHub REST API (create/update branch, commit files)
- Logo: pushed to repo as image asset
- Config: writes CustomerConfig.swift and PingConfig.swift to customer branch

### GitHub Branching Strategy
- `main` — base app, stable, no customer config
- `demo/southwest-airlines` — Southwest config
- `demo/whataburger` — Whataburger config
- `demo/exxon-mobil` — Exxon config
- Branches created/managed by configurator only

### Configurable Fields
| Category | Fields |
|----------|--------|
| Branding | Customer Name, Logo upload, Primary Color, Secondary Color, Tagline |
| PingOne | Environment ID, Client ID, Redirect URI |
| DaVinci | Login Policy ID, Registration Policy ID, Step-Up Flow ID |
| Display | Content tile titles/subtitles/icons, Screen visibility toggles |

### Live Preview Screens (iPhone frame)
1. Login Screen
2. Registration Screen
3. Home / Dashboard
4. Profile Page
5. Step-Up Auth Prompt

### Next Steps Panel Output (after Generate)
```bash
git fetch origin
git checkout demo/southwest-airlines
open ping-bxdemo-swift.xcodeproj
# Build and run in Xcode simulator
```

### Full Spec Document
`/mnt/user-data/uploads/SE_Demo_Configurator_Project_Plan.docx` (previously uploaded)

---

## Running the App

```bash
# Open in Xcode
open ~/Documents/ping-bxdemo-swift/ping-bxdemo-swift.xcodeproj
# Build and run on iPhone 16e simulator
```

## Claude Code Sessions

```bash
cd ~/Documents/ping-bxdemo-swift
claude --dangerously-skip-permissions
```

---

## Common Issues and Fixes

| Issue | Fix |
|-------|-----|
| `userSessionMismatch` after registration | Call signoff endpoint before startFlow() |
| Login fails after registration | signoff clears stale ST cookie |
| DaVinci Functions "Illegal return statement" | No `return` in Functions node JS — last expression is output |
| DaVinci Functions "parameters is not defined" | Use variableInputList + access as `parameters.varName` |
| Verify Email "identifier must be a uuid" | Use Create User output UUID, not email string |
| `returnSuccessResponseWidget` on registration | Use Http Send Success JSON Response instead |
| App shows blank/loading after registration | RegistrationViewModel needs fresh DaVinci instance |
| Token claims empty | PingOne app needs profile+email scopes in Resources tab |
| Build error after Claude Code prompt | Check for duplicate variable names, missing imports |
| Functions "parameters is not defined" with HTTP outputs | Don't map HTTP outputs directly → use Flow Instance Variable node first, then map from Variables output to Functions variableInputList |
| Read All Devices returns True with 0 devices | Use Functions node: `rawResponse.size > 0` to check actual device count |
| Create Device fails "mobilePhone required" | PATCH user profile with mobilePhone before calling Create Device |
| Dropdown not rendering in form | Add SingleSelectCollector case to ContinueNodeView switch statement |

---

## Key People

- **Dustin Rhodes** — Sales Engineer, Ping Identity, building this project
- **John Zaharakis** — SE colleague, collaborator
- **Test user:** `drhodes@dbri.net` (Dustin Rhodes, existing PingOne user)
- **Test users created during registration testing:** various `dustin@dbri.net` variants

---

## Session History Summary

Built in multiple sessions:
1. Started with React Native/Expo → switched to native SwiftUI for better SDK support
2. Scaffolded SwiftUI app with DaVinci SDK integration
3. Southwest Airlines branding via CustomerConfig.swift
4. Solved DaVinci SDK SwiftUI re-render issue (DavinciState wrapper pattern)
5. Built dynamic form renderer — renders whatever DaVinci returns
6. Login working: Enter details → tokens → HomeView → ProfileView with JWT claims
7. Built Registration flow end-to-end — fought through multiple DaVinci issues:
   - Functions node JS syntax (no return statements)
   - Variable access pattern (parameters.varName via variableInputList)
   - Verify Email UUID vs email address bug
   - returnSuccessResponseWidget causing userSessionMismatch on registration
8. Fixed post-registration login via PingOne signoff call
9. Profile tab showing full JWT claims
10. Completed ProfileManagementView — Edit Profile (PATCH API), Change Password, MFA Devices list, Sign Out
11. Replaced Safari WebView with native NavigationLink to ProfileManagementView
12. Added SingleSelectCollector (dropdown/radio) support to all ContinueNodeViews
13. Built full MFA login flow in DaVinci: device check → SMS OTP for existing → phone enrollment for new → verify → activate → save mobilePhone
14. Solved Functions node parameter mapping: Flow Instance Variable node required as intermediary

**Current state:** Full working demo — Login (with MFA) + Registration + Profile Management + Sign Out. All core CIAM flows complete.
