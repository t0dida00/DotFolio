import SwiftUI

/// Small caption above a field.
struct LabeledField<Field: View>: View {
    let title: String
    var required = false
    var optional = false
    @ViewBuilder let field: Field

    init(_ title: String, required: Bool = false, optional: Bool = false, @ViewBuilder field: () -> Field) {
        self.title = title
        self.required = required
        self.optional = optional
        self.field = field()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text.fieldTitle(title, required: required, optional: optional)
                .font(DS.Font.label)
                .foregroundStyle(.secondary)
            field
        }
    }
}
