import SwiftUI

/// Selectable row with icon, title and subtitle — the kit's `feedback/OptionRow.jsx`.
///
/// Used by the "What can you offer?" picker. The `isRecommended` flag is new: it
/// surfaces the kinds of help the dreamer actually asked for, so an offer is more
/// likely to be one they can use.
struct OptionRow: View {
    /// What the trailing edge shows. A row that picks a value in place gets a
    /// checkmark; a row that pushes to a further step gets a chevron.
    enum Accessory {
        case checkmark, chevron, none
    }

    let icon: String
    let title: String
    var subtitle: String? = nil
    var isSelected: Bool = false
    var isRecommended: Bool = false
    var accessory: Accessory = .checkmark
    /// Overrides the icon tile's colors — used where the option carries its own
    /// category palette (the offer kinds in `HelpSheet`).
    var tint: CategoryPalette? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: DreamSpace.s6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconForeground)
                    .frame(width: 40, height: 40)
                    .background(iconFill, in: DreamShape.sm)

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
                                .foregroundStyle(tint?.fg ?? DreamTheme.Accent.deep)
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

                switch accessory {
                case .checkmark:
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? DreamTheme.Accent.base : DreamTheme.Border.strong)
                case .chevron:
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DreamTheme.Text.tertiary)
                case .none:
                    EmptyView()
                }
            }
            .padding(DreamSpace.s6)
            .background(rowFill, in: DreamShape.lg)
            .overlay(DreamShape.lg.strokeBorder(rowBorder, lineWidth: 1))
            .contentShape(DreamShape.lg)
        }
        .buttonStyle(DreamPressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var rowFill: Color {
        if let tint, isRecommended { return tint.bg }
        return isSelected ? DreamTheme.Accent.tint : DreamTheme.Surface.card
    }

    private var rowBorder: Color {
        if let tint, isRecommended { return tint.fg }
        return isSelected ? DreamTheme.Border.accent : DreamTheme.Border.standard
    }

    private var iconFill: Color {
        if let tint { return isRecommended ? DreamTheme.Surface.card : tint.bg }
        return isSelected ? DreamTheme.Accent.soft : DreamTheme.Surface.sunken
    }

    private var iconForeground: Color {
        if let tint { return tint.fg }
        return isSelected ? DreamTheme.Accent.deep : DreamTheme.Text.secondary
    }
}
