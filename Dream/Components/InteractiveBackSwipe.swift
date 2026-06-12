import SwiftUI

/// Native-style "swipe from the left edge to go back" for screens presented as
/// `fullScreenCover` (which, unlike a `NavigationStack` push, has no built-in
/// interactive dismiss). A thin strip on the leading edge tracks a rightward
/// drag, translates the whole screen with the finger, and dismisses past a
/// threshold (or with enough flick velocity) — otherwise it springs back.
///
/// The strip is inset from the very top/bottom so it never swallows taps on a
/// top-left back button or a bottom CTA, and it's narrow enough not to interfere
/// with interior vertical scrolling.
private struct InteractiveBackSwipe: ViewModifier {
    /// When true, a successful swipe slides the content off to the right before
    /// running `onBack` — the native feel for dismissing a cover. When false
    /// (e.g. stepping back within a multi-step sheet that stays on screen) the
    /// content springs back to place and `onBack` just changes the step.
    let slideOff: Bool
    let onBack: () -> Void
    @State private var dragX: CGFloat = 0

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .offset(x: dragX)
                .overlay(alignment: .leading) {
                    Color.clear
                        .frame(width: 24)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 80)
                        .padding(.bottom, 100)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                                .onChanged { value in
                                    dragX = max(0, value.translation.width)
                                }
                                .onEnded { value in
                                    let distance = value.translation.width
                                    let projected = value.predictedEndTranslation.width
                                    if distance > 110 || projected > 240 {
                                        if slideOff {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                dragX = geometry.size.width
                                            }
                                        } else {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                                dragX = 0
                                            }
                                        }
                                        onBack()
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                            dragX = 0
                                        }
                                    }
                                }
                        )
                        .ignoresSafeArea()
                }
        }
    }
}

extension View {
    /// Adds a native-feeling left-edge swipe back. Set `slideOff: false` when the
    /// screen stays mounted after `onBack` (e.g. popping a step within a sheet).
    func interactiveBackSwipe(slideOff: Bool = true, _ onBack: @escaping () -> Void) -> some View {
        modifier(InteractiveBackSwipe(slideOff: slideOff, onBack: onBack))
    }
}

/// Applies `interactiveBackSwipe` only when an `onBack` handler exists (i.e. the
/// screen was presented over something), and is a no-op otherwise.
struct ConditionalBackSwipe: ViewModifier {
    let onBack: (() -> Void)?

    func body(content: Content) -> some View {
        if let onBack {
            content.interactiveBackSwipe(onBack)
        } else {
            content
        }
    }
}
