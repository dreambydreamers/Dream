import SwiftUI

/// Screen header — the kit's `content/PageHeader.jsx`.
///
/// The headline is sans-bold with a serif-italic accent word ("What's *happening*").
/// Use `wordmark` for the Dream logotype instead of a title.
struct PageHeader<Trailing: View>: View {
    var title: String = ""
    var accent: String? = nil
    var subtitle: String? = nil
    var showsWordmark: Bool = false
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: DreamSpace.s6) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(DreamTheme.Text.primary)
                        .padding(.top, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DreamPressStyle(scale: 0.9))
                .accessibilityLabel("Back")
            }

            VStack(alignment: .leading, spacing: DreamSpace.s3) {
                if showsWordmark {
                    DreamWordmark(size: 26, color: DreamTheme.Text.primary)
                } else {
                    DreamHeadline(title, accent: accent, size: 26)
                }

                if let subtitle {
                    Text(subtitle)
                        .dreamStyle(.body(13))
                        .foregroundStyle(DreamTheme.Text.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.horizontal, DreamSpace.screenGutter)
        .padding(.bottom, DreamSpace.s8)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String = "", accent: String? = nil, subtitle: String? = nil,
         showsWordmark: Bool = false, onBack: (() -> Void)? = nil) {
        self.init(title: title, accent: accent, subtitle: subtitle,
                  showsWordmark: showsWordmark, onBack: onBack) { EmptyView() }
    }
}
