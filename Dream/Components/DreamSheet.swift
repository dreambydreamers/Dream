import SwiftUI

/// Standard chrome for a presented sheet — the kit's `feedback/Sheet.jsx`.
///
/// Header (serif-accent headline + square close button), scrollable body, and an
/// optional footer separated by a hairline. Wrap a sheet's content in this so
/// CommentsSheet, HelpSheet and the share sheet stop diverging.
struct DreamSheet<Content: View, Footer: View>: View {
    let title: String
    var accent: String? = nil
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DreamSpace.s6) {
                DreamHeadline(title, accent: accent, size: 22)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DreamTheme.Text.secondary)
                        .frame(width: 32, height: 32)
                        .background(DreamTheme.Surface.card, in: DreamShape.sm)
                        .overlay(DreamShape.sm.strokeBorder(DreamTheme.Border.standard, lineWidth: 1))
                }
                .buttonStyle(DreamPressStyle(scale: 0.9))
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, DreamSpace.screenGutter)
            .padding(.top, DreamSpace.s9)
            .padding(.bottom, DreamSpace.s6)

            ScrollView {
                content().padding(.horizontal, DreamSpace.screenGutter)
            }

            footerBar
        }
        .background(DreamTheme.Surface.page)
    }

    @ViewBuilder
    private var footerBar: some View {
        if Footer.self != EmptyView.self {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(DreamTheme.Border.standard)
                    .frame(height: 1)

                footer()
                    .padding(.horizontal, DreamSpace.screenGutter)
                    .padding(.top, DreamSpace.s8)
                    .padding(.bottom, DreamSpace.s6)
            }
        }
    }
}

extension DreamSheet where Footer == EmptyView {
    init(title: String, accent: String? = nil, onClose: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, accent: accent, onClose: onClose, content: content) { EmptyView() }
    }
}
