import SwiftUI

/// The list of accounts the signed-in user has blocked, with an unblock action.
///
/// Reached from Edit Profile. The rows come from the `list_blocked_profiles`
/// RPC rather than a `profiles` read: a block hides the profile row from the
/// blocker too (migration 0036), so a normal fetch would return nothing and
/// this screen would show bare ids.
struct BlockedAccountsScreen: View {
    var onClose: () -> Void = {}

    @State private var blocked: [BlockedProfile] = []
    @State private var isLoading = true
    @State private var busyIds: Set<UUID> = []
    @State private var errorMessage: String?

    var body: some View {
        DreamSheet(title: "Blocked", accent: "accounts", onClose: onClose) {
            if isLoading {
                VStack(spacing: DreamSpace.s8) {
                    ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
                }
                .padding(.top, DreamSpace.s8)
            } else if blocked.isEmpty {
                EmptyState(
                    icon: "hand.raised",
                    title: "No blocked",
                    accent: "accounts",
                    message: "When you block someone, they show up here so you can undo it."
                )
                .padding(.top, DreamSpace.s10)
            } else {
                VStack(spacing: DreamSpace.s5) {
                    Text("Blocked accounts can't see your dreams or message you, and you won't see theirs.")
                        .dreamStyle(.body(13))
                        .foregroundStyle(DreamTheme.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, DreamSpace.s3)

                    ForEach(blocked) { profile in
                        row(profile)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .dreamStyle(.body(12))
                            .foregroundStyle(DreamTheme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.bottom, DreamSpace.s10)
            }
        } footer: {
            DreamButton(title: "Done", variant: .secondary, size: .md, fullWidth: true) { onClose() }
        }
        .task { await load() }
    }

    private func row(_ profile: BlockedProfile) -> some View {
        HStack(spacing: DreamSpace.s6) {
            Avatar(name: profile.displayName, seed: profile.avatarSeed,
                   size: 40, url: profile.avatarURL)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .dreamStyle(.ui(14))
                    .foregroundStyle(DreamTheme.Text.primary)
                Text("@\(profile.displayHandle)")
                    .dreamStyle(.body(12))
                    .foregroundStyle(DreamTheme.Text.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DreamButton(
                title: "Unblock",
                variant: .secondary,
                size: .sm,
                isBusy: busyIds.contains(profile.id)
            ) {
                unblock(profile)
            }
            .disabled(busyIds.contains(profile.id))
        }
        .padding(DreamSpace.s6)
        .background(DreamTheme.Surface.card, in: DreamShape.lg)
        .overlay(DreamShape.lg.strokeBorder(DreamTheme.Border.standard, lineWidth: 1))
    }

    private func load() async {
        blocked = await ModerationRepository.shared.blockedProfiles()
        isLoading = false
    }

    private func unblock(_ profile: BlockedProfile) {
        guard !busyIds.contains(profile.id) else { return }
        busyIds.insert(profile.id)
        errorMessage = nil
        Task {
            defer { busyIds.remove(profile.id) }
            do {
                try await ModerationRepository.shared.unblock(profile.id)
                blocked.removeAll { $0.id == profile.id }
            } catch {
                print("[BlockedAccountsScreen] unblock failed: \(error)")
                errorMessage = "Couldn't unblock @\(profile.displayHandle). Please try again."
            }
        }
    }
}
