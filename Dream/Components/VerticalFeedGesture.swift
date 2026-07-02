import SwiftUI
import UIKit

/// Installs a direction-aware UIPanGestureRecognizer into the view hierarchy.
///
/// Place this view as the FIRST child of the feed ZStack (with .allowsHitTesting(false)
/// so touches pass to cards). Because it is a sibling of the card views, self.superview
/// IS the ZStack's UIView — the shared ancestor of all cards.
///
/// Horizontal / vertical routing:
///   • Horizontal drags: shouldBegin returns false → our pan fails immediately →
///     the TabView UIScrollView can proceed with tab switching.
///   • Vertical drags: shouldBegin returns true → our pan succeeds. Additionally,
///     tabScrollView.panGestureRecognizer.require(toFail: ourPan) is established at
///     install time, so the TabView's pan can NEVER run while our pan is active.
///     This replaces the fragile isScrollEnabled toggle and prevents the
///     UIScrollView's canCancelContentTouches from sending premature .cancelled
///     events to our gesture mid-swipe.
///   • System-level .cancelled (app moves to background, phone call, etc.):
///     onCancelled fires so the caller can spring the card back to center.
struct VerticalFeedGesture: UIViewRepresentable {
    var onChanged:   (CGFloat) -> Void           // cumulative translation.y
    var onEnded:     (CGFloat, CGFloat) -> Void  // translation.y, velocity.y
    var onCancelled: () -> Void                  // spring-back, no commit

    func makeUIView(context: Context) -> _AnchorView {
        _AnchorView(coordinator: context.coordinator)
    }

    func updateUIView(_ view: _AnchorView, context: Context) {
        context.coordinator.onChanged   = onChanged
        context.coordinator.onEnded     = onEnded
        context.coordinator.onCancelled = onCancelled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded, onCancelled: onCancelled)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged:   (CGFloat) -> Void
        var onEnded:     (CGFloat, CGFloat) -> Void
        var onCancelled: () -> Void
        private(set) var installedPan: UIPanGestureRecognizer?

        init(onChanged:   @escaping (CGFloat) -> Void,
             onEnded:     @escaping (CGFloat, CGFloat) -> Void,
             onCancelled: @escaping () -> Void) {
            self.onChanged   = onChanged
            self.onEnded     = onEnded
            self.onCancelled = onCancelled
        }

        func install(in hostView: UIView) {
            guard installedPan == nil else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.delegate = self
            hostView.addGestureRecognizer(pan)
            installedPan = pan
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view else { return }
            let t  = pan.translation(in: view)
            let vy = pan.velocity(in: view).y
            switch pan.state {
            case .changed:
                onChanged(t.y)
            case .ended:
                onEnded(t.y, vy)
            case .cancelled, .failed:
                // System-level interruption — caller should spring the card back.
                onCancelled()
            default:
                break
            }
        }

        // Use translation for direction — velocity can be near-zero at gesture start.
        func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
            guard let pan = gr as? UIPanGestureRecognizer else { return true }
            let t = pan.translation(in: pan.view)
            guard abs(t.x) + abs(t.y) > 0 else { return true }
            return abs(t.y) > abs(t.x)
        }

        func gestureRecognizer(_ gr: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            return true
        }
    }

    // MARK: - Anchor UIView

    final class _AnchorView: UIView {
        private weak var coordinator: Coordinator?
        private var installed = false

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard !installed, window != nil else { return }
            installed = true
            DispatchQueue.main.async { [weak self] in self?.walkAndInstall() }
        }

        private func walkAndInstall() {
            guard let coordinator else { return }

            // Walk up 3 levels to clear SwiftUI modifier wrapper UIViews and reach
            // the ZStack's actual UIView — the common ancestor of all card views.
            var target: UIView = self
            for _ in 0..<3 {
                guard let parent = target.superview else { break }
                if parent is UIScrollView { break }
                target = parent
            }
            coordinator.install(in: target)

            // Find the TabView's UIScrollView and set up require(toFail:) so the
            // scroll view's pan must wait for our pan to either fail (horizontal
            // → tab switch OK) or succeed (vertical → TabView blocked entirely,
            // no canCancelContentTouches interference mid-swipe).
            guard let ourPan = coordinator.installedPan else { return }
            var ancestor: UIView = target
            while let parent = ancestor.superview {
                if let sv = parent as? UIScrollView {
                    sv.panGestureRecognizer.require(toFail: ourPan)
                    break
                }
                ancestor = parent
            }
        }
    }
}
