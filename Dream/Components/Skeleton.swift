import SwiftUI

/// Shimmer placeholder — the kit's `feedback/Skeleton.jsx`.
///
/// The app previously showed a bare `ProgressView()` while loading, which gives no
/// sense of what is arriving. A skeleton that matches the shape of the incoming
/// content makes the wait feel shorter and stops the layout jumping when it lands.
struct Skeleton: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var radius: CGFloat = DreamRadius.sm
    var isCircle: Bool = false

    var body: some View {
        TimelineView(.animation) { timeline in
            // A 1.4s sweep, driven off the shared clock so every skeleton on screen
            // shimmers in phase rather than each starting from its own appearance.
            let t = timeline.date.timeIntervalSinceReferenceDate
            let progress = (t.truncatingRemainder(dividingBy: 1.4)) / 1.4

            shape
                .fill(DreamTheme.Skeleton.base)
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: DreamTheme.Skeleton.sheen, location: 0.5),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    // Sweep from fully off the leading edge to fully off the trailing one.
                    .offset(x: (progress * 2 - 1) * (width ?? 320))
                    .clipShape(shape)
                }
        }
        .frame(width: width, height: isCircle ? width ?? height : height)
        .accessibilityHidden(true)
    }

    private var shape: AnyShape {
        isCircle ? AnyShape(Circle()) : AnyShape(DreamShape.radius(radius))
    }
}

/// Placeholder for a media card with an author row beneath it.
struct SkeletonFeedCard: View {
    var mediaHeight: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: DreamSpace.s6) {
            Skeleton(height: mediaHeight, radius: DreamRadius.lg)
            HStack(spacing: DreamSpace.s5) {
                Skeleton(width: 38, height: 38, radius: DreamRadius.sm)
                VStack(alignment: .leading, spacing: DreamSpace.s3) {
                    Skeleton(width: 150, height: 13)
                    Skeleton(width: 90, height: 11)
                }
            }
        }
    }
}

/// Placeholder for an avatar + two-line row — Activity, Messages, comments.
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: DreamSpace.s7) {
            Skeleton(width: 42, height: 42, radius: DreamRadius.sm)
            VStack(alignment: .leading, spacing: DreamSpace.s3) {
                Skeleton(width: 190, height: 13)
                Skeleton(width: 76, height: 10)
            }
            Spacer(minLength: 0)
        }
    }
}
