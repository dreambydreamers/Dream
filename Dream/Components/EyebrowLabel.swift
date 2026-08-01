import SwiftUI

/// Uppercase micro-label above a section — the kit's `content/EyebrowLabel.jsx`.
///
/// Wide tracking (0.16em) at a small size is what makes this read as a label
/// rather than as small body text.
struct EyebrowLabel: View {
    let text: String
    var color: Color = DreamTheme.Text.tertiary

    var body: some View {
        Text(text)
            .dreamStyle(.label)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
