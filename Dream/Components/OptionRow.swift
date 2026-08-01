import SwiftUI

/// Selectable row with icon, title and subtitle — the kit's `feedback/OptionRow.jsx`.
///
/// Used by the "What can you offer?" picker. The `isRecommended` flag is new: it
/// surfaces the kinds of help the dreamer actually asked for, so an offer is more
/// likely to be one they can use.
struct OptionRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var isSelected: Bool = false
    var isRecommended: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: DreamSpace.s6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? DreamTheme.Accent.deep : DreamTheme.Text.secondary)
                    .frame(width: 40, height: 40)
                    .background(
                        isSelected ? DreamTheme.Accent.soft : DreamTheme.Surface.sunken,
                        in: DreamShape.sm
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: DreamSpace.s4) {
                        Text(title)
                            .dreamStyle(.ui(14))
                            .foregroundStyle(DreamTheme.Text.primary)

                        if isRecommended {
                            Text("Asked for")
                                .dreamStyle(.ui(10, weight: .bold))
                                .textCase(.uppercase)
                                .tracking(0.8)
                                .foregroundStyle(DreamTheme.Accent.deep)
                                .padding(.horizontal, DreamSpace.s3)
                                .padding(.vertical, 3)
                                .background(DreamTheme.Accent.soft, in: Capsule())
                        }
                    }

                    if let subtitle {
                        Text(subtitle)
                            .dreamStyle(.body(12))
                            .foregroundStyle(DreamTheme.Text.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? DreamTheme.Accent.base : DreamTheme.Border.strong)
            }
            .padding(DreamSpace.s6)
            .background(
                isSelected ? DreamTheme.Accent.tint : DreamTheme.Surface.card,
                in: DreamShape.lg
            )
            .overlay(
                DreamShape.lg.strokeBorder(
                    isSelected ? DreamTheme.Border.accent : DreamTheme.Border.standard,
                    lineWidth: 1
                )
            )
            .contentShape(DreamShape.lg)
        }
        .buttonStyle(DreamPressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
