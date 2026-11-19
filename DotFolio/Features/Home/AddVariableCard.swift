import DotFolioCore
import DotFolioModels
import SwiftData
import SwiftUI

/// "Add variable", pinned to the bottom of the detail column.
/// Layout: Name 30% · Value 70%, then Service 20% · Account 30% · Link 50%.
struct AddVariableCard: View {
    let environment: ProjectEnvironment
    var nameFocused: FocusState<Bool>.Binding

    @Environment(\.modelContext) private var context
    @Environment(\.secretStore) private var secrets

    @State private var newKey = ""
    @State private var newValue = ""
    @State private var newService = ""
    @State private var newAccount = ""
    @State private var newLink = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Add variable", systemImage: "plus.circle")
                    .font(.callout.weight(.semibold))
                    .symbolMotion(.bounce)
                Spacer()
                Text("to \(environment.name)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ProportionalRow(fractions: [0.3, 0.7]) {
                LabeledField("Name") {
                    TextField("", text: $newKey, prompt: Text("API_KEY"))
                        .font(.system(.body, design: .monospaced))
                        .focused(nameFocused)
                }
                LabeledField("Value") {
                    SecureField("", text: $newValue, prompt: Text("Paste the secret value"))
                        .font(.system(.body, design: .monospaced))
                }
            }

            ProportionalRow(fractions: [0.2, 0.3, 0.5]) {
                LabeledField("Service") {
                    TextField("", text: $newService, prompt: Text("e.g. Firebase"))
                }
                LabeledField("Account") {
                    TextField("", text: $newAccount, prompt: Text("email or username"))
                }
                LabeledField("Link") {
                    TextField("", text: $newLink, prompt: Text(verbatim: "https://console.example.com (optional)"))
                }
            }

            HStack {
                Text(errorMessage ?? "The value is saved to your Keychain.")
                    .font(.caption)
                    .foregroundStyle(errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                    .lineLimit(2)
                Spacer()
                Button(action: add) {
                    Label("Add Variable", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .symbolMotion(.bounce)
                .buttonBorderShape(.capsule)
                .keyboardShortcut(.defaultAction)
                .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
                .clickableCursor()
            }
        }
        .textFieldStyle(.roundedBorder)
        .onSubmit(add)
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
    }

    private func add() {
        do {
            try VariableEditor.add(key: newKey, value: newValue, service: newService, account: newAccount, link: newLink,
                                   to: environment, context: context, secrets: secrets)
            errorMessage = nil
            newKey = ""; newValue = ""; newService = ""; newAccount = ""; newLink = ""
            nameFocused.wrappedValue = true
        } catch let failure as VariableEditor.Failure {
            errorMessage = failure.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Small caption above a field.
private struct LabeledField<Field: View>: View {
    let title: String
    @ViewBuilder let field: Field

    init(_ title: String, @ViewBuilder field: () -> Field) {
        self.title = title
        self.field = field()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            field
        }
    }
}

/// Lays children out side by side, each taking a fraction of the width.
private struct ProportionalRow: Layout {
    let fractions: [CGFloat]
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        let height = zip(subviews, widths(for: width)).map { $0.sizeThatFits(.init(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(for: bounds.width)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: .init(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func widths(for total: CGFloat) -> [CGFloat] {
        let available = max(0, total - spacing * CGFloat(max(0, fractions.count - 1)))
        return fractions.map { available * $0 }
    }
}

