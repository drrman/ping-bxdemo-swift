import SwiftUI

struct ManualFormField {
    let key: String
    let label: String
    let isPassword: Bool
}

struct ManualFormView: View {
    let fields: [ManualFormField]
    let submitLabel: String
    let onSubmit: ([String: String]) -> Void

    @State private var values: [String: String] = [:]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(fields, id: \.key) { field in
                PingTextField(
                    placeholder: field.label,
                    text: binding(for: field.key),
                    isSecure: field.isPassword
                )
            }

            PingButton(title: submitLabel) {
                onSubmit(values)
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }
}

#Preview {
    ManualFormView(
        fields: [
            ManualFormField(key: "username", label: "Email Address", isPassword: false),
            ManualFormField(key: "password", label: "Password", isPassword: true),
        ],
        submitLabel: "Sign In"
    ) { values in
        print(values)
    }
    .padding()
}
