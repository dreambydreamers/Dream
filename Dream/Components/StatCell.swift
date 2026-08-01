import SwiftUI

struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: DreamSpace.s1) {
            Text(value)
                .dreamStyle(.title(22))
                .foregroundStyle(DreamTheme.Text.primary)
            Text(label)
                .dreamStyle(.label)
                .foregroundStyle(DreamTheme.Text.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A row of stats separated by hairlines — the kit's `content/StatRow.jsx`.
/// Wrap in a `DreamSurface` for the carded treatment used on Profile and detail.
struct StatRow: View {
    struct Stat: Identifiable {
        let id = UUID()
        let value: String
        let label: String

        init(_ value: String, _ label: String) {
            self.value = value
            self.label = label
        }
    }

    let stats: [Stat]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                if index > 0 {
                    Rectangle()
                        .fill(DreamTheme.Border.standard)
                        .frame(width: 1, height: 28)
                }
                StatCell(value: stat.value, label: stat.label)
            }
        }
    }
}
