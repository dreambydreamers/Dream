import SwiftUI

struct JourneyTimeline: View {
    let steps: [JourneyStep]
    let accent: Color

    private var currentIndex: Int? {
        for i in steps.indices.reversed() where steps[i].done { return i }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { i, step in
                row(index: i, step: step)
            }
        }
        .background(alignment: .leading) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(DreamTheme.line)
                    .frame(width: 2)
                if let ci = currentIndex {
                    GeometryReader { geo in
                        let frac = (CGFloat(ci) + 0.5) / CGFloat(max(steps.count, 1))
                        Rectangle()
                            .fill(accent)
                            .frame(width: 2, height: geo.size.height * frac)
                    }
                }
            }
            .padding(.leading, 9)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func row(index i: Int, step: JourneyStep) -> some View {
        let isCurrent = i == currentIndex
        let isFuture = !step.done

        HStack(alignment: .top, spacing: 14) {
            node(isFuture: isFuture, isCurrent: isCurrent)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(step.stage)
                        .font(DreamTheme.Font.text(15, weight: .semibold))
                        .foregroundStyle(isFuture ? DreamTheme.ink3 : DreamTheme.ink)
                    Spacer(minLength: 8)
                    Text(step.date)
                        .font(DreamTheme.Font.text(11, weight: .medium))
                        .tracking(0.3)
                        .foregroundStyle(isFuture ? DreamTheme.ink3 : DreamTheme.ink2)
                }
                Text(step.note)
                    .font(DreamTheme.Font.text(13))
                    .foregroundStyle(isFuture ? DreamTheme.ink3 : DreamTheme.ink2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func node(isFuture: Bool, isCurrent: Bool) -> some View {
        ZStack {
            Circle()
                // An unreached step reads as an empty well, not as page ground —
                // the timeline sits on a card, so `page` would disappear into it.
                .fill(isFuture ? DreamTheme.Surface.card : accent)
                .overlay(
                    Circle().strokeBorder(isFuture ? DreamTheme.line : accent, lineWidth: 2)
                )
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(isCurrent ? accent.opacity(0.22) : .clear)
                        .frame(width: 28, height: 28)
                )

            if isCurrent {
                Circle().fill(.white).frame(width: 6, height: 6)
            } else if !isFuture {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 28, height: 28)
    }
}
