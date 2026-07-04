import SwiftUI

struct ProfilePlaceholder: View {
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        ZStack {
            DreamTheme.paper.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Profile")
                    .font(DreamTheme.Font.display(40, weight: .regular, italic: true))
                    .foregroundStyle(DreamTheme.ink)
                Text("Your dreams, your skills, the people you've helped.")
                    .font(DreamTheme.Font.text(14))
                    .foregroundStyle(DreamTheme.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    Task { await auth.signOut() }
                } label: {
                    Text("Sign out")
                        .font(DreamTheme.Font.text(15, weight: .semibold))
                        .foregroundStyle(DreamTheme.ink)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .overlay {
                            Capsule().stroke(DreamTheme.line, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
            }
        }
    }
}
