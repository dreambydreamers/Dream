import SwiftUI

struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DreamTheme.Font.display(22, weight: .medium))
                .foregroundStyle(DreamTheme.ink)
            Text(label.uppercased())
                .font(DreamTheme.Font.text(11, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(DreamTheme.ink2)
        }
        .frame(maxWidth: .infinity)
    }
}
