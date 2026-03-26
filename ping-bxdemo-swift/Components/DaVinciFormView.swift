import SwiftUI
import PingDavinci
import PingOrchestrate

struct DaVinciFormView: View {
    let node: ContinueNode
    let onSubmit: (ContinueNode) -> Void

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Array(node.collectors.enumerated()), id: \.offset) { _, collector in
                collectorView(for: collector)
            }
        }
    }

    @ViewBuilder
    private func collectorView(for collector: any Collector) -> some View {
        if let textCollector = collector as? TextCollector {
            TextCollectorField(collector: textCollector)
        } else if let passwordCollector = collector as? PasswordCollector {
            PasswordCollectorField(collector: passwordCollector)
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

#Preview {
    Text("DaVinci Form requires live DaVinci node")
        .foregroundColor(.secondary)
}
