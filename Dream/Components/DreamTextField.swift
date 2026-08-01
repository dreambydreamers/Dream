import SwiftUI

/// The kit's `forms/TextField.jsx`.
///
/// Replaces four divergent inline treatments (Auth, EditProfile, Explore search,
/// the composers). Structure is eyebrow label → 48pt field → hint/error row, with
/// the border moving to the accent on focus.
///
/// The text color is always set explicitly. An unstyled `TextField` falls back to
/// `.primary`, which is a real bug here: it inverts with the system appearance
/// independently of the field's own fill.
struct DreamTextField: View {
    let label: String?
    var placeholder: String = ""
    @Binding var text: String
    /// SF Symbol shown at the leading edge.
    var icon: String? = nil
    var isSecure: Bool = false
    var keyboard: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences
    /// Renders a multi-line editor instead of a single-line field.
    var lineLimit: Int? = nil
    var characterLimit: Int? = nil
    var hint: String? = nil
    var error: String? = nil

    @FocusState private var isFocused: Bool

    private var isMultiline: Bool { (lineLimit ?? 1) > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: DreamSpace.s2) {
            if let label {
                Text(label)
                    .dreamStyle(.label)
                    .foregroundStyle(DreamTheme.Text.tertiary)
            }

            HStack(alignment: isMultiline ? .top : .center, spacing: DreamSpace.s6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(isFocused ? DreamTheme.Text.accent : DreamTheme.Text.tertiary)
                        .padding(.top, isMultiline ? 2 : 0)
                        .animation(DreamMotion.smooth(DreamMotion.fast), value: isFocused)
                }

                field
                    .dreamStyle(.body(15))
                    .foregroundStyle(DreamTheme.Text.primary)
                    .tint(DreamTheme.Accent.base)
                    .focused($isFocused)
                    .keyboardType(keyboard)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(autocapitalization)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DreamSpace.s7)
            .padding(.vertical, isMultiline ? 13 : 0)
            .frame(minHeight: 48)
            .background(DreamTheme.Surface.card, in: DreamShape.lg)
            .overlay(DreamShape.lg.strokeBorder(borderColor, lineWidth: 1))
            .animation(DreamMotion.smooth(DreamMotion.fast), value: isFocused)
            .onChange(of: text) { _, new in
                if let characterLimit, new.count > characterLimit {
                    text = String(new.prefix(characterLimit))
                }
            }

            if let error {
                footnote(error, icon: "exclamationmark.circle", color: DreamTheme.Status.error)
            } else if let hint {
                footnote(hint, icon: nil, color: DreamTheme.Text.tertiary)
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        if isSecure {
            SecureField(placeholder, text: $text)
        } else if isMultiline {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(lineLimit ?? 4, reservesSpace: true)
        } else {
            TextField(placeholder, text: $text)
        }
    }

    private func footnote(_ text: String, icon: String?, color: Color) -> some View {
        HStack(spacing: DreamSpace.s3) {
            if let icon {
                Image(systemName: icon).font(.system(size: 12))
            }
            Text(text).dreamStyle(.ui(11, weight: .regular))
        }
        .foregroundStyle(color)
    }

    private var borderColor: Color {
        if error != nil { return DreamTheme.Status.error }
        return isFocused ? DreamTheme.Border.accent : DreamTheme.Border.standard
    }
}

/// Search field with a leading glass and a clear affordance — `forms/SearchField.jsx`.
struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Search dreams and people"
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: DreamSpace.s5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DreamTheme.Text.tertiary)

            Group {
                if let focus {
                    TextField(placeholder, text: $text).focused(focus)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .dreamStyle(.body(15))
            .foregroundStyle(DreamTheme.Text.primary)
            .tint(DreamTheme.Accent.base)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DreamTheme.Text.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, DreamSpace.s7)
        .frame(height: 44)
        .background(DreamTheme.Surface.card, in: DreamShape.lg)
        .overlay(DreamShape.lg.strokeBorder(DreamTheme.Border.standard, lineWidth: 1))
    }
}
