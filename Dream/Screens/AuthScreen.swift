import SwiftUI

/// Email + password sign-in / sign-up. Presented from `OnboardingScreen`.
/// Drives `AuthService`; on success the auth state flips and `RootView`
/// swaps in the main shell automatically, so there's no explicit dismissal.
struct AuthScreen: View {
    enum Mode { case signIn, signUp }

    @ObservedObject private var auth = AuthService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    // One binding per field rather than an enum: `DreamTextField` takes a
    // `FocusState<Bool>.Binding`, which keeps its border styling and the caller's
    // keyboard chaining driven by the same state.
    @FocusState private var nameFocused: Bool
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool

    init(mode: Mode = .signIn) {
        _mode = State(initialValue: mode)
    }

    private var isSignUp: Bool { mode == .signUp }

    private var canSubmit: Bool {
        guard email.contains("@"), password.count >= 6 else { return false }
        if isSignUp { return !name.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    var body: some View {
        ZStack(alignment: .top) {
            DreamTheme.Surface.page.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if auth.awaitingEmailConfirmation {
                        confirmationNotice
                    } else {
                        form
                    }
                }
                .padding(.horizontal, DreamSpace.screenGutter)
                .padding(.top, 80)
                .padding(.bottom, DreamSpace.s14)
            }
            .scrollDismissesKeyboard(.interactively)

            closeButton
        }
        .onChange(of: mode) { _, _ in auth.errorMessage = nil }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DreamSpace.s3) {
            if isSignUp {
                DreamHeadline("Create your", accent: "account", size: 30)
            } else {
                DreamHeadline("Welcome", accent: "back", size: 30)
            }
            Text(isSignUp
                 ? "Share what you dream of building."
                 : "Sign in to pick up where you left off.")
                .dreamStyle(.body(15))
                .foregroundStyle(DreamTheme.Text.secondary)
        }
        .padding(.bottom, DreamSpace.s13)
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: DreamSpace.s8) {
            if isSignUp {
                DreamTextField(label: "Name", placeholder: "How should we call you?",
                               text: $name, icon: "person",
                               textContentType: .name, autocapitalization: .words,
                               focus: $nameFocused)
                    .submitLabel(.next)
                    .onSubmit { emailFocused = true }
            }

            DreamTextField(label: "Email", placeholder: "you@example.com",
                           text: $email, icon: "envelope",
                           keyboard: .emailAddress, textContentType: .emailAddress,
                           autocapitalization: .never, focus: $emailFocused)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .onSubmit { passwordFocused = true }

            DreamTextField(label: "Password", placeholder: "At least 6 characters",
                           text: $password, icon: "lock", isSecure: true,
                           textContentType: isSignUp ? .newPassword : .password,
                           autocapitalization: .never, focus: $passwordFocused)
                .submitLabel(isSignUp ? .join : .go)
                .onSubmit(submit)

            if let message = auth.errorMessage {
                errorRow(message)
            }

            DreamButton(
                title: isSignUp ? "Create account" : "Sign in",
                fullWidth: true,
                isEnabled: canSubmit,
                isBusy: auth.isBusy,
                action: submit
            )
            .padding(.top, DreamSpace.s2)

            modeToggle
                .padding(.top, DreamSpace.s4)
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DreamSpace.s4) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
            Text(message)
                .dreamStyle(.body(13))
        }
        .foregroundStyle(DreamTheme.Status.error)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeToggle: some View {
        HStack(spacing: DreamSpace.s2) {
            Text(isSignUp ? "Already have an account?" : "New here?")
                .foregroundStyle(DreamTheme.Text.secondary)
            Button {
                withAnimation(DreamMotion.smooth()) {
                    mode = isSignUp ? .signIn : .signUp
                }
            } label: {
                Text(isSignUp ? "Sign in" : "Create an account")
                    .foregroundStyle(DreamTheme.Text.accent)
                    .fontWeight(.semibold)
            }
            .buttonStyle(DreamPressStyle())
        }
        .dreamStyle(.ui(13, weight: .regular))
        .frame(maxWidth: .infinity)
    }

    // MARK: - Email confirmation state

    private var confirmationNotice: some View {
        EmptyState(
            icon: "envelope.badge",
            title: "Check your",
            accent: "inbox",
            message: "We sent a confirmation link to \(email). Tap it to finish creating your account, then come back and sign in.",
            actionTitle: "Back to sign in",
            action: {
                auth.awaitingEmailConfirmation = false
                mode = .signIn
            }
        )
    }

    // MARK: - Actions

    private func submit() {
        guard canSubmit, !auth.isBusy else { return }
        nameFocused = false
        emailFocused = false
        passwordFocused = false
        Task {
            if isSignUp {
                await auth.signUp(email: email, password: password, name: name, handle: "")
            } else {
                await auth.signIn(email: email, password: password)
            }
        }
    }

    private var closeButton: some View {
        HStack {
            IconButton(systemName: "xmark", accessibilityLabel: "Close",
                       variant: .solid, size: 38) { dismiss() }
            Spacer()
        }
        .padding(.horizontal, DreamSpace.s10)
        .padding(.top, DreamSpace.s6)
    }
}

#Preview {
    AuthScreen()
}
