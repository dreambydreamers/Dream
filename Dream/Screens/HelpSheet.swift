import SwiftUI

enum OfferKind: String, CaseIterable, Identifiable {
    case fund, mentor, design, connect, custom
    var id: String { rawValue }

    var skill: String {
        switch self {
        case .fund: return "Funding"
        case .mentor: return "Mentorship"
        case .design: return "Design"
        case .connect: return "Network"
        case .custom: return "Other"
        }
    }
    var label: String {
        switch self {
        case .fund: return "Back this dream"
        case .mentor: return "Mentor for an hour"
        case .design: return "Design support"
        case .connect: return "Make an intro"
        case .custom: return "Something else"
        }
    }
    var sub: String {
        switch self {
        case .fund: return "A one-time contribution"
        case .mentor: return "A call to share what you know"
        case .design: return "Brand, signage, or web"
        case .connect: return "Connect them to someone"
        case .custom: return "Tell them in your own words"
        }
    }
    var icon: String {
        switch self {
        case .fund: return "dollarsign"
        case .mentor: return "cup.and.saucer.fill"
        case .design: return "paintbrush.fill"
        case .connect: return "arrow.up.right"
        case .custom: return "sparkle"
        }
    }
    var palette: CategoryPalette {
        switch self {
        case .fund: return DreamCategory.impact.palette
        case .mentor: return DreamCategory.education.palette
        case .design: return DreamCategory.art.palette
        case .connect: return DreamCategory.tech.palette
        case .custom: return .init(fg: DreamTheme.ink2, bg: DreamTheme.bg, tint: DreamTheme.bg)
        }
    }
    var requiresConfig: Bool { self != .custom }
}

private enum SheetMode { case pick, configure, review }

struct HelpSheet: View {
    let dream: Dream
    var onClose: () -> Void = {}

    @State private var mode: SheetMode = .pick
    @State private var selected: OfferKind?

    @State private var amount: Int = 100
    @State private var duration: Int = 60
    @State private var slot: String = "thu"
    @State private var scope: Set<String> = ["logo"]
    @State private var introWho: String = "Lila Park — runs Sparrow Café in Fort Greene"
    @State private var introWhy: String = "Lila opened Sparrow on a similar budget last year."
    @State private var note: String = ""

    @State private var sending = false
    @State private var sendError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch mode {
                case .pick: pickStep
                case .configure, .review: configureStep
                }
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle(mode == .pick ? "Offer your help" : (selected?.label ?? ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DreamTheme.ink2)
                    }
                }
            }
        }
        // Swipe back steps within the flow (configure → pick) before closing the
        // whole sheet, mirroring the in-flow "Back" button.
        .interactiveBackSwipe(slideOff: false) { goBack() }
    }

    /// Left-edge swipe-back: pop to the offer picker if we're deeper in the
    /// flow, otherwise dismiss the sheet.
    private func goBack() {
        if mode == .pick {
            onClose()
        } else {
            mode = .pick
        }
    }

    /// Persists the offer via the `create_help_offer` RPC, which also opens the
    /// conversation and notifies the dream owner. The RPC de-duplicates, so a
    /// repeat tap reuses the existing offer rather than creating another.
    private func send() async {
        sending = true
        sendError = nil
        defer { sending = false }
        do {
            _ = try await HelpOfferRepository.shared.createOffer(
                dreamId: dream.id,
                skill: selected?.skill ?? "Other",
                message: composedMessage)
            onClose()
        } catch {
            sendError = "Couldn't send your offer. Please try again."
        }
    }

    /// A human-readable summary of the configured offer, stored as the offer's
    /// message + opening chat line.
    private var composedMessage: String {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch selected {
        case .fund:
            return "Offering $\(amount)." + (trimmedNote.isEmpty ? "" : " \(trimmedNote)")
        case .mentor:
            return "Happy to mentor for \(duration) min (\(slot))." + (trimmedNote.isEmpty ? "" : " \(trimmedNote)")
        case .design:
            let items = scope.sorted().joined(separator: ", ")
            return "Design help: \(items)." + (trimmedNote.isEmpty ? "" : " \(trimmedNote)")
        case .connect:
            return "Intro to \(introWho). \(introWhy)"
        case .custom, .none:
            return trimmedNote
        }
    }

    // MARK: - Pick

    private var pickStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Avatar(name: dream.name, seed: dream.avatarSeed, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("You're offering to help")
                            .font(DreamTheme.Font.text(13))
                            .foregroundStyle(DreamTheme.ink2)
                        Text(dream.title)
                            .font(DreamTheme.Font.text(14, weight: .semibold))
                            .foregroundStyle(DreamTheme.ink)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(DreamTheme.bg))
                .padding(.bottom, 18)

                eyebrow("What can you offer?").padding(.bottom, 14)

                VStack(spacing: 8) {
                    ForEach(OfferKind.allCases) { kind in
                        offerRow(kind)
                    }
                }
                .padding(.bottom, 18)

                HStack(alignment: .top, spacing: 10) {
                    Text("✦")
                    Text("An offer is a starting point. You'll be able to talk through details once they accept.")
                        .font(DreamTheme.Font.text(12))
                        .foregroundStyle(Color(hex: 0x5A4A30))
                        .lineSpacing(2)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(DreamTheme.cream))
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 60)
        }
    }

    private func offerRow(_ kind: OfferKind) -> some View {
        let wanted = dream.help.contains(kind.skill)
        let p = kind.palette
        return Button {
            selected = kind
            mode = kind.requiresConfig ? .configure : .review
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(wanted ? Color.white : p.bg)
                    Image(systemName: kind.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(p.fg)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.label)
                        .font(DreamTheme.Font.text(15, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink)
                    Text(kind.sub)
                        .font(DreamTheme.Font.text(12))
                        .foregroundStyle(DreamTheme.ink2)
                }
                Spacer(minLength: 8)
                if wanted {
                    Text("ASKED FOR")
                        .font(DreamTheme.Font.text(9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(p.fg)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DreamTheme.ink3)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(wanted ? p.bg : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(wanted ? p.fg : DreamTheme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Configure

    private var configureStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selected {
                    case .fund:    fundConfig
                    case .mentor:  timeConfig
                    case .design:  scopeConfig
                    case .connect: whoConfig
                    case .custom, .none: customConfig
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }

            Divider().background(DreamTheme.line)
            VStack(spacing: 10) {
                if let sendError {
                    Text(sendError)
                        .font(DreamTheme.Font.text(13))
                        .foregroundStyle(DreamCategory.health.palette.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 10) {
                    Button("Back") { mode = .pick }
                        .font(DreamTheme.Font.text(14, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink2)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).strokeBorder(DreamTheme.line, lineWidth: 1))
                    PrimaryButton(title: sending ? "Sending…" : "Send offer") {
                        guard !sending else { return }
                        Task { await send() }
                    }
                    .disabled(sending)
                    .opacity(sending ? 0.7 : 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .background(Color.white)
        }
    }

    private var fundConfig: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("Amount").padding(.bottom, 12)
            VStack(spacing: 4) {
                Text("$\(amount)")
                    .font(DreamTheme.Font.display(56, weight: .regular))
                    .tracking(-2)
                    .foregroundStyle(DreamTheme.ink)
                Text("USD · charged when \(dream.name.split(separator: " ").first.map(String.init) ?? "they") accepts")
                    .font(DreamTheme.Font.text(12))
                    .foregroundStyle(DreamTheme.ink2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .background(RoundedRectangle(cornerRadius: 18).fill(DreamTheme.bg))
            .padding(.bottom, 16)

            LazyVGrid(columns: Array(repeating: .init(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach([25, 50, 100, 250, 500, 1000], id: \.self) { p in
                    Button { amount = p } label: {
                        Text("$\(p)")
                            .font(DreamTheme.Font.text(15, weight: .semibold))
                            .foregroundStyle(amount == p ? .white : DreamTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(amount == p ? DreamTheme.blue : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(amount == p ? DreamTheme.blue : DreamTheme.line, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 20)

            noteField(placeholder: "A few words for \(dream.name.split(separator: " ").first.map(String.init) ?? "them")...")
        }
    }

    private var timeConfig: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("How long").padding(.bottom, 12)
            HStack(spacing: 8) {
                ForEach([(30, "30 min"), (60, "1 hour"), (90, "1.5 hours")], id: \.0) { val, label in
                    Button { duration = val } label: {
                        Text(label)
                            .font(DreamTheme.Font.text(14, weight: .semibold))
                            .foregroundStyle(duration == val ? .white : DreamTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(duration == val ? DreamTheme.blue : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(duration == val ? DreamTheme.blue : DreamTheme.line, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 24)

            eyebrow("Pick a window").padding(.bottom, 12)
            let slots: [(String, String, String)] = [
                ("tue", "Tue", "May 12 · 5pm"),
                ("wed", "Wed", "May 13 · 7pm"),
                ("thu", "Thu", "May 14 · 6pm"),
                ("fri", "Fri", "May 15 · 4pm"),
            ]
            LazyVGrid(columns: [.init(.flexible(), spacing: 8), .init(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(slots, id: \.0) { id, label, sub in
                    Button { slot = id } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label)
                                .font(DreamTheme.Font.text(15, weight: .bold))
                                .foregroundStyle(DreamTheme.ink)
                            Text(sub)
                                .font(DreamTheme.Font.text(11))
                                .foregroundStyle(DreamTheme.ink2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(slot == id ? DreamTheme.blueSoft : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(slot == id ? DreamTheme.blue : DreamTheme.line, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 20)

            Text("They'll see your availability and pick a time that works.")
                .font(DreamTheme.Font.text(13))
                .foregroundStyle(DreamTheme.ink2)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(DreamTheme.bg))
        }
    }

    private var scopeConfig: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("What you'll cover").padding(.bottom, 12)
            let items: [(String, String, String)] = [
                ("logo", "Logo & wordmark", "~6 hrs"),
                ("signage", "Space signage", "~10 hrs"),
                ("web", "Simple website", "~12 hrs"),
                ("menu", "Menu design", "~4 hrs"),
            ]
            VStack(spacing: 8) {
                ForEach(items, id: \.0) { id, label, time in
                    let on = scope.contains(id)
                    Button {
                        if on { scope.remove(id) } else { scope.insert(id) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label)
                                    .font(DreamTheme.Font.text(15, weight: .semibold))
                                    .foregroundStyle(DreamTheme.ink)
                                Text("\(time) · pro bono")
                                    .font(DreamTheme.Font.text(12))
                                    .foregroundStyle(DreamTheme.ink2)
                            }
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(on ? DreamTheme.blue : Color.white)
                                    .overlay(Circle().strokeBorder(on ? DreamTheme.blue : DreamTheme.line, lineWidth: 2))
                                    .frame(width: 22, height: 22)
                                if on {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(on ? DreamTheme.blueSoft : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(on ? DreamTheme.blue : DreamTheme.line, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 24)

            noteField(placeholder: "Anything else...")
        }
    }

    private var whoConfig: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("Who's the intro").padding(.bottom, 12)
            TextField("e.g. Lila, who runs Sparrow Café", text: $introWho, axis: .vertical)
                .font(DreamTheme.Font.text(15))
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(DreamTheme.bg))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DreamTheme.line, lineWidth: 1))
                .padding(.bottom, 16)

            eyebrow("Why they'd be helpful").padding(.bottom, 12)
            TextField("Their relevance...", text: $introWhy, axis: .vertical)
                .font(DreamTheme.Font.text(14))
                .lineLimit(4...8)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(DreamTheme.bg))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DreamTheme.line, lineWidth: 1))
        }
    }

    private var customConfig: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("Your offer").padding(.bottom, 12)
            noteField(placeholder: "Tell them in your own words...", minHeight: 140)
        }
    }

    private func noteField(placeholder: String, minHeight: CGFloat = 90) -> some View {
        TextField(placeholder, text: $note, axis: .vertical)
            .font(DreamTheme.Font.text(14))
            .lineLimit(4...10)
            .padding(14)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(DreamTheme.bg))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DreamTheme.line, lineWidth: 1))
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(DreamTheme.Font.text(11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(DreamTheme.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
