import SwiftUI

/// "Report" flow: pick a reason, optionally add detail, submit.
///
/// Two steps in one sheet (`step`), mirroring `HelpSheet`'s `mode`: the reason
/// list, then a confirmation with an optional note. Submitting is deliberately
/// hard to get wrong — the reason list is the whole first screen and nothing is
/// preselected, so a mis-tap can't file a report.
struct ReportSheet: View {
    /// What is being reported, for both the payload and the copy.
    let target: ReportTarget
    let targetId: UUID
    /// The author, so a moderator can see who is being reported even after the
    /// content is deleted. Nil for content with no resolvable author.
    var reportedUserId: UUID?
    /// Snapshot of the reported text, stored with the report.
    var excerpt: String?
    /// Offered after submitting, when there is someone to block.
    var subjectName: String?
    var onClose: () -> Void = {}
    /// Called when the user chooses to also block the author.
    var onBlock: (() -> Void)?

    private enum Step { case pickReason, detail, submitted }

    @State private var step: Step = .pickReason
    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var noteFocused: Bool

    var body: some View {
        DreamSheet(title: titleLead, accent: titleAccent, onClose: onClose) {
            switch step {
            case .pickReason: reasonList
            case .detail:     detailForm
            case .submitted:  confirmation
            }
        } footer: {
            footer
        }
        .keyboardDoneButton()
        // The sheet owns its own back behaviour: from the detail step an edge
        // swipe returns to the reason list rather than discarding the report.
        .interactiveBackSwipe(slideOff: false) { goBack() }
    }

    // MARK: - Copy

    private var titleLead: String {
        switch step {
        case .pickReason, .detail: return "Report this"
        case .submitted:           return "Thanks for"
        }
    }

    private var titleAccent: String? {
        switch step {
        case .pickReason, .detail: return targetNoun
        case .submitted:           return "telling us"
        }
    }

    private var targetNoun: String {
        switch target {
        case .dream:   return "dream"
        case .video:   return "video"
        case .photo:   return "photo"
        case .comment: return "comment"
        case .message: return "message"
        case .profile: return "account"
        }
    }

    // MARK: - Steps

    private var reasonList: some View {
        VStack(alignment: .leading, spacing: DreamSpace.s6) {
            Text("What's going on? This is anonymous — we don't tell them who reported.")
                .dreamStyle(.body(13))
                .foregroundStyle(DreamTheme.Text.secondary)
                .padding(.bottom, DreamSpace.s2)

            ForEach(ReportReason.allCases) { option in
                OptionRow(
                    icon: icon(for: option),
                    title: option.label,
                    subtitle: option.detail,
                    isSelected: reason == option,
                    accessory: .chevron
                ) {
                    reason = option
                    withAnimation(DreamMotion.smooth()) { step = .detail }
                }
            }
        }
        .padding(.bottom, DreamSpace.s10)
    }

    private var detailForm: some View {
        VStack(alignment: .leading, spacing: DreamSpace.s7) {
            if let reason {
                HStack(spacing: DreamSpace.s5) {
                    Image(systemName: icon(for: reason))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DreamTheme.Accent.deep)
                        .frame(width: 34, height: 34)
                        .background(DreamTheme.Accent.soft, in: DreamShape.sm)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reason.label)
                            .dreamStyle(.ui(14))
                            .foregroundStyle(DreamTheme.Text.primary)
                        Text(reason.detail)
                            .dreamStyle(.body(12))
                            .foregroundStyle(DreamTheme.Text.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }

            // Self-harm reports get support resources rather than a bare form —
            // the person reporting may be the one who needs them.
            if reason == .selfHarm {
                DreamNote(
                    icon: "heart.text.square",
                    text: "If you or someone you know is in crisis, contact your local emergency services or a crisis line. In the US, call or text 988."
                )
            }

            VStack(alignment: .leading, spacing: DreamSpace.s4) {
                Text("Anything else? (optional)")
                    .dreamStyle(.ui(13))
                    .foregroundStyle(DreamTheme.Text.primary)
                TextField("Add context that helps us review this…", text: $note, axis: .vertical)
                    .dreamStyle(.body(14))
                    .foregroundStyle(DreamTheme.Text.primary)
                    .lineLimit(3...6)
                    .focused($noteFocused)
                    .padding(DreamSpace.s6)
                    .background(DreamTheme.Surface.card, in: DreamShape.lg)
                    .overlay(DreamShape.lg.strokeBorder(DreamTheme.Border.standard, lineWidth: 1))
                Text("\(note.count)/1000")
                    .dreamStyle(.body(11))
                    .foregroundStyle(DreamTheme.Text.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let errorMessage {
                Text(errorMessage)
                    .dreamStyle(.body(12))
                    .foregroundStyle(DreamTheme.error)
            }
        }
        .padding(.bottom, DreamSpace.s10)
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: DreamSpace.s7) {
            DreamNote(
                icon: "checkmark.shield",
                text: "We've received your report and our team will review it. We remove content that breaks our rules and take action on repeat offenders."
            )
            if let subjectName, onBlock != nil {
                Text("Want to stop seeing \(subjectName) altogether? Blocking hides their content from you and stops them contacting you.")
                    .dreamStyle(.body(13))
                    .foregroundStyle(DreamTheme.Text.secondary)
            }
        }
        .padding(.bottom, DreamSpace.s10)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        switch step {
        case .pickReason:
            // A real footer rather than EmptyView: DreamSheet decides whether to
            // draw its hairline from the Footer *type*, which is one
            // _ConditionalContent here — an EmptyView branch would still leave
            // a stray divider and padding.
            DreamButton(title: "Cancel", variant: .secondary, size: .md, fullWidth: true) { onClose() }
        case .detail:
            HStack(spacing: DreamSpace.s5) {
                DreamButton(title: "Back", variant: .secondary, size: .md) { goBack() }
                DreamButton(
                    title: isSubmitting ? "Sending…" : "Submit report",
                    variant: .primary, size: .md, fullWidth: true,
                    isBusy: isSubmitting
                ) {
                    submit()
                }
                .disabled(isSubmitting || reason == nil)
            }
        case .submitted:
            if let onBlock, let subjectName {
                HStack(spacing: DreamSpace.s5) {
                    DreamButton(title: "Done", variant: .secondary, size: .md) { onClose() }
                    DreamButton(title: "Block \(subjectName)", variant: .primary, size: .md, fullWidth: true) {
                        onBlock()
                        onClose()
                    }
                }
            } else {
                DreamButton(title: "Done", variant: .primary, size: .md, fullWidth: true) { onClose() }
            }
        }
    }

    // MARK: - Actions

    private func goBack() {
        switch step {
        case .pickReason: onClose()
        case .detail:     withAnimation(DreamMotion.smooth()) { step = .pickReason }
        case .submitted:  onClose()
        }
    }

    private func submit() {
        guard let reason, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        noteFocused = false
        Task {
            defer { isSubmitting = false }
            do {
                try await ModerationRepository.shared.report(
                    target: target,
                    targetId: targetId,
                    reportedUserId: reportedUserId,
                    reason: reason,
                    note: note,
                    excerpt: excerpt
                )
                withAnimation(DreamMotion.smooth()) { step = .submitted }
            } catch {
                print("[ReportSheet] submit failed: \(error)")
                errorMessage = "Couldn't send that report. Check your connection and try again."
            }
        }
    }

    private func icon(for reason: ReportReason) -> String {
        switch reason {
        case .spam:                 return "tray.full"
        case .harassment:           return "person.crop.circle.badge.exclamationmark"
        case .hate:                 return "exclamationmark.bubble"
        case .violence:             return "exclamationmark.triangle"
        case .sexualContent:        return "eye.slash"
        case .selfHarm:             return "heart.text.square"
        case .misinformation:       return "questionmark.circle"
        case .impersonation:        return "person.2.slash"
        case .intellectualProperty: return "c.circle"
        case .other:                return "ellipsis.circle"
        }
    }
}
