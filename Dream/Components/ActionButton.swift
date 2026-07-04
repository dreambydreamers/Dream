import SwiftUI

/// Right-rail action button used over the discover feed.
struct ActionButton: View {
    let systemImage: String
    let label: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.32))
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)

                Text(label)
                    .font(DreamTheme.Font.text(11, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 64)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
