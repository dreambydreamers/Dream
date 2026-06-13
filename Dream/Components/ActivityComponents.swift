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
}
