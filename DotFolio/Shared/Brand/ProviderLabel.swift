import SwiftUI

struct ProviderLabel: View {
    let brand: BrandMark
    let title: String

    var body: some View {
        HStack(spacing: DS.Space.s) {
            brand.image.resizable().scaledToFit().frame(width: 16, height: 16)
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }
}
