import SwiftUI

struct OnboardingScreen: View {
    var onSignIn: () -> Void
    var onCreateAccount: () -> Void = {}

    var body: some View {
        ZStack(alignment: .top) {
            DreamTheme.paper.ignoresSafeArea()

            WelcomeSkyBackground()
                .frame(height: 460)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, DreamTheme.paper],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 110)
                }
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 14) {
                    Text("Dream")
                        .font(DreamTheme.Font.display(68, weight: .light, italic: true))
                        .foregroundStyle(DreamTheme.blueDeep)
                        .tracking(-2)
                        .padding(.bottom, 8)

                    (
                        Text("Where dreams\n")
                            .font(DreamTheme.Font.display(28, weight: .regular))
                        + Text("meet")
                            .font(DreamTheme.Font.display(28, weight: .light, italic: true))
                        + Text(" opportunity.")
                            .font(DreamTheme.Font.display(28, weight: .regular))
                    )
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DreamTheme.ink)
                    .tracking(-0.6)
                    .lineSpacing(2)
                    .frame(maxWidth: 320)

                    Text("Share what you dream of building. Find the people who'll help you build it.")
                        .font(DreamTheme.Font.text(14))
                        .foregroundStyle(DreamTheme.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 300)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 60)

                VStack(spacing: 18) {
                    PrimaryButton(title: "Sign in with Apple", icon: "applelogo", action: onSignIn)

                    HStack(spacing: 4) {
                        Text("New here?")
                            .foregroundStyle(DreamTheme.ink2)
                        Button(action: onCreateAccount) {
                            Text("Create an account")
                                .foregroundStyle(DreamTheme.blueDeep)
                                .fontWeight(.semibold)
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(DreamTheme.blueDeep)
                                        .frame(height: 1)
                                        .offset(y: 2)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    .font(DreamTheme.Font.text(14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
    }
}

#Preview {
    OnboardingScreen(onSignIn: {})
}
