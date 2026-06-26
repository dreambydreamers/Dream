import SwiftUI

/// Compact relative time ("just now", "4m", "2h", "3d") for activity rows.
func relativeTimeLabel(_ date: Date) -> String {
    let s = max(0, Date().timeIntervalSince(date))
    switch s {
    case ..<60:        return "just now"
    case ..<3600:      return "\(Int(s / 60))m"
    case ..<86400:     return "\(Int(s / 3600))h"
    case ..<604800:    return "\(Int(s / 86400))d"
    default:
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

/// Status chip for a help offer (Pending / Accepted / In Progress / …).
struct OfferStatusPill: View {
    let status: HelpOfferStatus
    var body: some View {
        Text(status.label.uppercased())
            .font(DreamTheme.Font.text(9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(status.palette.fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(status.palette.bg))
    }
}

/// Small presence dot — green when the other person is online.
struct OnlineDot: View {
    let online: Bool
    var body: some View {
        Circle()
            .fill(online ? Color(hex: 0x2F9E54) : DreamTheme.ink3.opacity(0.4))
            .frame(width: 9, height: 9)
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
    }
}

/// Animated "typing…" three-dot indicator.
struct TypingIndicator: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(DreamTheme.ink3)
                    .frame(width: 6, height: 6)
                    .opacity(phase == Double(i) ? 1 : 0.3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14).fill(DreamTheme.bg))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: false)) {
                phase = 2
            }
        }
    }
}

/// A single chat message. System messages render as a centered note; user
/// messages as left/right bubbles.
struct MessageBubble: View {
    let message: MessageDTO
    let isMine: Bool
    var showSeen: Bool = false
    var sharePreview: SharedVideoPreview? = nil

    var body: some View {
        if message.isSystem {
            Text(message.body)
                .font(DreamTheme.Font.text(12))
                .foregroundStyle(DreamTheme.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(DreamTheme.cream))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
        } else if message.isDreamShare {
            VStack(alignment: isMine ? .trailing : .leading, spacing: 5) {
                sharedVideoCard
                if showSeen {
                    Text("Seen")
                        .font(DreamTheme.Font.text(10, weight: .medium))
                        .foregroundStyle(DreamTheme.ink3)
                        .padding(.trailing, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        } else {
            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                Text(message.body)
                    .font(DreamTheme.Font.text(15))
                    .foregroundStyle(isMine ? .white : DreamTheme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isMine ? DreamTheme.blue : DreamTheme.bg)
                    )
                if showSeen {
                    Text("Seen")
                        .font(DreamTheme.Font.text(10, weight: .medium))
                        .foregroundStyle(DreamTheme.ink3)
                        .padding(.trailing, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        }
    }

    private var sharedVideoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if let posterURL = sharePreview?.posterURL {
                    AsyncImage(url: posterURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            shareFallback
                        }
                    }
                } else {
                    shareFallback
                }

                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("Dream video")
                        .font(DreamTheme.Font.text(11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.45), in: Capsule())
                .padding(10)
            }
            .frame(width: 220, height: 132)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(sharePreview?.title ?? message.body)
                    .font(DreamTheme.Font.text(14, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink)
                    .lineLimit(2)
                Text(message.body)
                    .font(DreamTheme.Font.text(12))
                    .foregroundStyle(DreamTheme.ink2)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(width: 220, alignment: .leading)
            .background(Color.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(DreamTheme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
    }

    private var shareFallback: some View {
        ScenePoster(category: sharePreview?.category ?? .tech)
            .frame(width: 220, height: 132)
    }
}
