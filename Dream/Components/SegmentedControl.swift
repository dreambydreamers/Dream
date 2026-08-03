import SwiftUI

/// The kit's `navigation/SegmentedControl.jsx`.
///
/// Replaces two unrelated implementations — Activity's scrolling capsule pills and
/// Profile's underline tab bar — with one control. The `onMedia` variant is the
/// same component over video, used for Discover's For you / Following switch.
struct SegmentedControl<Value: Hashable>: View {
    struct Option: Identifiable {
        let id: Value
        let label: String

        init(_ id: Value, _ label: String) {
            self.id = id
            self.label = label
        }
    }

    let options: [Option]
    @Binding var selection: Value
    /// Glass treatment for placement over video.
    var onMedia: Bool = false
    /// Stretch to fill the available width instead of hugging its labels.
    var fullWidth: Bool = false

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: DreamSpace.s1) {
            ForEach(options) { option in
                let isActive = option.id == selection

                Button {
                    withAnimation(DreamMotion.smooth(DreamMotion.fast)) { selection = option.id }
                } label: {
                    Text(option.label)
                        .dreamStyle(.ui(12))
                        .foregroundStyle(foreground(isActive: isActive))
                        .frame(maxWidth: fullWidth ? .infinity : nil)
                        .padding(.vertical, 7)
                        .padding(.horizontal, DreamSpace.s7)
                        .background {
                            if isActive {
                                DreamShape.xs
                                    .fill(activeFill)
                                    .matchedGeometryEffect(id: "segment", in: indicator)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background {
            if onMedia {
                DreamShape.sm
                    .fill(DreamTheme.Glass.fill)
                    .background(.ultraThinMaterial, in: DreamShape.sm)
                    .environment(\.colorScheme, .dark)
                    .overlay(DreamShape.sm.strokeBorder(DreamTheme.Glass.stroke, lineWidth: 1))
            } else {
                DreamShape.sm.fill(DreamTheme.Surface.sunken)
            }
        }
        .clipShape(DreamShape.sm)
    }

    private var activeFill: Color {
        onMedia ? DreamTheme.OnMedia.base : DreamTheme.Surface.card
    }

    private func foreground(isActive: Bool) -> Color {
        if isActive {
            return onMedia ? Color(hex: 0x14171A) : DreamTheme.Text.primary
        }
        return onMedia ? DreamTheme.OnMedia.dim : DreamTheme.Text.tertiary
    }
}
