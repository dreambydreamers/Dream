import SwiftUI

/// Circular avatar. Renders an uploaded profile picture when `url` is set,
/// otherwise a procedurally generated seed-gradient + initials fallback.
struct Avatar: View {
    let name: String
    let seed: Int
    var size: CGFloat = 40
    /// Optional uploaded profile picture. Falls back to the gradient on
    /// nil / load failure.
    var url: URL? = nil

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private var colors: [Color] {
        let pair = DreamAvatarGradient.pair(seed: seed)
        return [pair.0, pair.1]
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
