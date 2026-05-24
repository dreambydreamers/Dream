import SwiftUI

/// Placeholder for the prototype's illustrated video posters.
/// Uses a category-tinted gradient; richer scenes can replace this later.
struct ScenePoster: View {
    let category: DreamCategory

    var body: some View {
        let p = category.palette
        LinearGradient(
            colors: [p.fg.opacity(0.85), p.fg.opacity(0.45), p.bg],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Warm dawn gradient used on the Welcome screen.
struct WelcomeSkyBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0xF4E8D0),
                    Color(hex: 0xF0DAB8),
                    Color(hex: 0xE5C6A8),
                    Color(hex: 0xD4A89E),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Sun
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xFFE5B4),
                            Color(hex: 0xF4B074),
                            Color(hex: 0xD4815A),
                        ],
                        center: .init(x: 0.35, y: 0.35),
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 280, height: 280)
                .offset(y: -60)

            // Horizon silhouettes
            GeometryReader { geo in
                let w = geo.size.width
                Path { p in
                    p.move(to: .init(x: 0, y: 130))
                    p.addLine(to: .init(x: w * 0.18, y: 80))
                    p.addLine(to: .init(x: w * 0.38, y: 105))
                    p.addLine(to: .init(x: w * 0.60, y: 60))
                    p.addLine(to: .init(x: w * 0.83, y: 95))
                    p.addLine(to: .init(x: w,     y: 70))
                    p.addLine(to: .init(x: w,     y: 200))
                    p.addLine(to: .init(x: 0,     y: 200))
                    p.closeSubpath()
                }
                .fill(Color(hex: 0x4A2E23).opacity(0.35))
                .offset(y: geo.size.height - 200)
            }
        }
    }
}
