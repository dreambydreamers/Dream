import SwiftUI

enum FollowButtonStyle {
    case fullWidth
    case detail
    case feed
}

struct FollowButton: View {
    let isFollowing: Bool
    var style: FollowButtonStyle = .fullWidth
    var isBusy: Bool = false
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Text(isFollowing ? "Following" : "Follow")
                .font(font)
                .foregroundStyle(foreground)
                .frame(maxWidth: style == .fullWidth ? .infinity : nil)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(Capsule().fill(background))
                .overlay(Capsule().strokeBorder(stroke, lineWidth: strokeWidth))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.65 : 1)
    }

    private var font: Font {
        switch style {
        case .fullWidth:
            return DreamTheme.Font.text(14, weight: .semibold)
        case .detail:
            return DreamTheme.Font.text(13, weight: .semibold)
        case .feed:
            return DreamTheme.Font.text(12, weight: .semibold)
        }
    }

    private var foreground: Color {
        switch style {
        case .feed:
            return .white
        default:
            return isFollowing ? DreamTheme.blueDeep : .white
        }
    }

    private var background: Color {
        switch style {
        case .feed:
            return Color.white.opacity(0.18)
        default:
            return isFollowing ? .white : DreamTheme.blue
        }
    }

    private var stroke: Color {
        switch style {
        case .feed:
            return Color.white.opacity(0.3)
        default:
            return DreamTheme.blue
        }
    }

    private var strokeWidth: CGFloat {
        style == .feed ? 0.5 : 1.5
    }

    private var horizontalPadding: CGFloat {
        switch style {
        case .fullWidth: return 0
        case .detail: return 16
        case .feed: return 10
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .fullWidth: return 11
        case .detail: return 7
        case .feed: return 4
        }
    }
}
