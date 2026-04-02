import SwiftUI
import PingDavinci
import PingOrchestrate
import PingProtect

struct DaVinciFormView: View {
    let node: ContinueNode
    let onSubmit: (ContinueNode) -> Void

    private var hasOnlyProtectCollectors: Bool {
        let visibleCollectors = node.collectors.filter {
            $0 is TextCollector || $0 is PasswordCollector || $0 is SubmitCollector ||
            $0 is FlowCollector || $0 is SingleSelectCollector
        }
        return visibleCollectors.isEmpty && node.collectors.contains(where: { $0 is ProtectCollector })
    }

    var body: some View {
        if hasOnlyProtectCollectors {
            ProgressView("Verifying device...")
                .onAppear {
                    Task {
                        for collector in node.collectors {
                            if let protect = collector as? ProtectCollector {
                                let _ = await protect.collect()
                            }
                        }
                        onSubmit(node)
                    }
                }
        } else {
            VStack(spacing: 16) {
                if !node.name.isEmpty && node.name != "Start Login" {
                    Text(node.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                ForEach(Array(node.collectors.enumerated()), id: \.offset) { _, collector in
                    collectorView(for: collector)
                }
            }
        }
    }

    @ViewBuilder
    private func collectorView(for collector: any Collector) -> some View {
        if let textCollector = collector as? TextCollector {
            TextCollectorField(collector: textCollector)
        } else if let passwordCollector = collector as? PasswordCollector {
            PasswordCollectorField(collector: passwordCollector)
        } else if let singleSelect = collector as? SingleSelectCollector {
            SingleSelectField(collector: singleSelect)
        } else if let protectCollector = collector as? ProtectCollector {
            EmptyView()
                .onAppear {
                    Task {
                        let _ = await protectCollector.collect()
                    }
                }
        } else if let submitCollector = collector as? SubmitCollector {
            PingButton(title: submitCollector.label.isEmpty ? "Submit" : submitCollector.label) {
                onSubmit(node)
            }
        } else if let flowCollector = collector as? FlowCollector {
            Button(flowCollector.label) {
                onSubmit(node)
            }
            .font(.callout)
            .foregroundColor(CustomerConfig.current.primaryColor)
        }
    }
}

private struct TextCollectorField: View {
    @ObservedObject var collector: TextCollectorObservable

    init(collector: TextCollector) {
        self.collector = TextCollectorObservable(collector: collector)
    }

    var body: some View {
        PingTextField(
            placeholder: collector.label,
            text: $collector.value,
            isSecure: false
        )
    }
}

private struct PasswordCollectorField: View {
    @ObservedObject var collector: PasswordCollectorObservable

    init(collector: PasswordCollector) {
        self.collector = PasswordCollectorObservable(collector: collector)
    }

    var body: some View {
        PingTextField(
            placeholder: collector.label,
            text: $collector.value,
            isSecure: true
        )
    }
}

// Observable wrappers to bridge SDK collectors with SwiftUI bindings
private class TextCollectorObservable: ObservableObject {
    let collector: TextCollector
    var label: String { collector.label }

    var value: String {
        get { collector.value }
        set {
            objectWillChange.send()
            collector.value = newValue
        }
    }

    init(collector: TextCollector) {
        self.collector = collector
    }
}

private class PasswordCollectorObservable: ObservableObject {
    let collector: PasswordCollector
    var label: String { collector.label }

    var value: String {
        get { collector.value }
        set {
            objectWillChange.send()
            collector.value = newValue
        }
    }

    init(collector: PasswordCollector) {
        self.collector = collector
    }
}

// MARK: - SingleSelectField (Dropdown/Radio)

struct SingleSelectField: View {
    let collector: SingleSelectCollector
    @State private var selectedValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(collector.label)
                .font(.caption)
                .foregroundColor(.secondary)

            Menu {
                ForEach(collector.options, id: \.value) { option in
                    Button(option.label) {
                        selectedValue = option.value
                        collector.value = option.value
                    }
                }
            } label: {
                HStack {
                    Text(selectedLabel)
                        .foregroundColor(selectedValue.isEmpty ? .gray : .primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
            }
        }
        .onAppear {
            selectedValue = collector.value
            // Default to first option if nothing selected
            if selectedValue.isEmpty, let first = collector.options.first {
                selectedValue = first.value
                collector.value = first.value
            }
        }
    }

    private var selectedLabel: String {
        collector.options.first(where: { $0.value == selectedValue })?.label ?? "Select an option"
    }
}

#Preview {
    Text("DaVinci Form requires live DaVinci node")
        .foregroundColor(.secondary)
}
