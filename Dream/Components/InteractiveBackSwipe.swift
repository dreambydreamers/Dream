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
    /// When true, a successful swipe dismisses immediately after the threshold is
    /// crossed. When false (e.g. stepping back within a multi-step sheet that
    /// stays on screen) the content springs back to place and `onBack` changes
    /// the step.
    let slideOff: Bool
    let onBack: () -> Void
    @State private var dragX: CGFloat = 0
    @State private var didCommit = false

    func body(content: Content) -> some View {
        GeometryReader { _ in
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
                                    guard !didCommit else { return }
                                    // Suppress implicit ancestor animations while the finger
                                    // is moving, or the drag lags behind the gesture.
                                    var tx = Transaction()
                                    tx.isContinuous = true
                                    tx.disablesAnimations = true
                                    withTransaction(tx) {
                                        let distance = max(0, value.translation.width)
                                        dragX = slideOff ? min(distance * 0.12, 24) : distance
                                    }
                                    if slideOff, shouldCommit(value) {
                                        commitBack()
                                    }
                                }
                                .onEnded { value in
                                    guard !didCommit else { return }
                                    if shouldCommit(value) {
                                        if slideOff {
                                            // Do not animate the content all the way off-screen
                                            // before dismissing: NavigationStack/fullScreenCover
                                            // hosts often have only a blank background behind
                                            // this view, which causes a white flash. Commit the
                                            // pop immediately and let the previous screen appear.
                                            commitBack()
                                        } else {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                                dragX = 0
                                            }
                                            onBack()
                                        }
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

    private func shouldCommit(_ value: DragGesture.Value) -> Bool {
        value.translation.width > 90 || value.predictedEndTranslation.width > 220
    }

    private func commitBack() {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            didCommit = true
            dragX = 0
            onBack()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            didCommit = false
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
