import SwiftUI

struct GlassCircleButton: View {
    let systemName: String
    let accessibilityLabel: String
    var size: CGFloat = 38
    var fontSize: CGFloat = 16
    var foreground: Color = .white
    var background: Color = Color.black.opacity(0.45)
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(background, in: Circle())
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
