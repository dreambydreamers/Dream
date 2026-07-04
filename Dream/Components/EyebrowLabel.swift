import SwiftUI

struct EyebrowLabel: View {
    let text: String
    var color: Color = DreamTheme.ink2

    var body: some View {
        Text(text.uppercased())
            .font(DreamTheme.Font.text(11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
