import SwiftUI

/// Selectable chip — the kit's `forms/ChipSelect.jsx`.
///
/// One treatment for what were two inline copies: skill chips in EditProfile and
/// help-need chips in Create.
struct DreamChip: View {
    let label: String
    var icon: String? = nil
    var isSelected: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: DreamSpace.s3) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .medium))
                }
                Text(label).dreamStyle(.ui(12))
            }
            .foregroundStyle(isSelected ? DreamTheme.Action.primaryForeground : DreamTheme.Text.secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, DreamSpace.s4)
            .background(isSelected ? DreamTheme.Accent.base : DreamTheme.Surface.card, in: DreamShape.sm)
            .overlay(
                DreamShape.sm.strokeBorder(isSelected ? .clear : DreamTheme.Border.standard, lineWidth: 1)
            )
            .contentShape(DreamShape.sm)
        }
        .buttonStyle(DreamPressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A row or wrapped block of chips backing a single or multiple selection.
///
/// `scrolls: true` gives the horizontal rail Explore uses for categories;
/// otherwise chips wrap via the existing `FlowLayout`.
struct ChipSelect<Value: Hashable>: View {
    struct Option: Identifiable {
        let id: Value
        let label: String
        let icon: String?

        init(_ id: Value, _ label: String, icon: String? = nil) {
            self.id = id
            self.label = label
            self.icon = icon
        }
    }

    let options: [Option]
    @Binding var selection: Set<Value>
    /// When false, picking an option replaces the selection instead of toggling.
    var allowsMultiple: Bool = false
    var scrolls: Bool = false

    var body: some View {
        if scrolls {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DreamSpace.s2) { chips }
                    .padding(.horizontal, DreamSpace.screenGutter)
            }
            // Let the rail bleed to the screen edges while its content stays gutter-aligned.
            .padding(.horizontal, -DreamSpace.screenGutter)
        } else {
            FlowLayout(spacing: DreamSpace.s2, lineSpacing: DreamSpace.s2) { chips }
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(options) { option in
            DreamChip(
                label: option.label,
                icon: option.icon,
                isSelected: selection.contains(option.id)
            ) {
                withAnimation(DreamMotion.smooth(DreamMotion.fast)) { toggle(option.id) }
            }
        }
    }

    private func toggle(_ value: Value) {
        guard allowsMultiple else {
            selection = [value]
            return
        }
        if selection.contains(value) {
            selection.remove(value)
        } else {
            selection.insert(value)
        }
    }
}
