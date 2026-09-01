import SwiftUI

struct OnboardingScreen: View {
    @State private var authMode: AuthScreen.Mode?

    var body: some View {
        ZStack(alignment: .top) {
            DreamTheme.Surface.page.ignoresSafeArea()

            WelcomeSkyBackground()
                .frame(height: 460)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, DreamTheme.Surface.page],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 110)
                }
                .overlay(alignment: .topLeading) {
                    DreamWordmark(size: 24, color: DreamTheme.Accent.deep)
                        .padding(.horizontal, DreamSpace.s10)
                        .padding(.top, DreamSpace.safeTop)
                }
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: DreamSpace.s6) {
                    // The kit's headline pattern: sans-bold with a single
                    // serif-italic accent word, not an all-serif setting.
                    DreamHeadline("Where dreams meet", accent: "opportunity", size: 30)

                    Text("Share what you dream of building. Find the people who'll help you build it.")
                        .dreamStyle(.body(15, relaxed: true))
                        .foregroundStyle(DreamTheme.Text.secondary)
                        .frame(maxWidth: 300, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DreamSpace.screenGutter)
                .padding(.bottom, DreamSpace.s11)

                VStack(spacing: DreamSpace.s6) {
                    DreamButton(title: "Get started", trailingIcon: "arrow.right", fullWidth: true) {
                        authMode = .signUp
                    }

                    Button { authMode = .signIn } label: {
                        HStack(spacing: DreamSpace.s2) {
                            Text("Already have an account?")
                                .foregroundStyle(DreamTheme.Text.secondary)
                            Text("Sign in")
                                .foregroundStyle(DreamTheme.Text.accent)
                                .fontWeight(.semibold)
                        }
                        .dreamStyle(.ui(13, weight: .regular))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DreamPressStyle())
                }
                .padding(.horizontal, DreamSpace.screenGutter)
                .padding(.bottom, DreamSpace.s14)
            }
        }
        .fullScreenCover(item: $authMode) { mode in
            AuthScreen(mode: mode)
        }
    }
}

extension AuthScreen.Mode: Identifiable {
    public var id: Int { hashValue }
}

#Preview {
    OnboardingScreen()
}
