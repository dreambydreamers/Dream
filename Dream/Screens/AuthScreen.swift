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
    @FocusState private var focused: Field?

    private enum Field { case name, email, password }

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
            DreamTheme.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if auth.awaitingEmailConfirmation {
                        confirmationNotice
                    } else {
                        form
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 80)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            closeButton
        }
        .onChange(of: mode) { _, _ in auth.errorMessage = nil }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isSignUp ? "Create your\naccount" : "Welcome\nback")
                .font(DreamTheme.Font.display(34, weight: .regular))
                .foregroundStyle(DreamTheme.ink)
                .lineSpacing(2)
            Text(isSignUp
                 ? "Share what you dream of building."
                 : "Sign in to pick up where you left off.")
                .font(DreamTheme.Font.text(15))
                .foregroundStyle(DreamTheme.ink2)
        }
        .padding(.bottom, 36)
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: 16) {
            if isSignUp {
                field(
                    "Name", text: $name, field: .name,
                    icon: "person", submitLabel: .next,
                    onSubmit: { focused = .email }
                )
                .textContentType(.name)
            }

            field(
                "Email", text: $email, field: .email,
                icon: "envelope", submitLabel: .next,
                onSubmit: { focused = .password }
            )
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            field(
                "Password", text: $password, field: .password,
                icon: "lock", secure: true,
                submitLabel: isSignUp ? .join : .go,
                onSubmit: submit
            )
            .textContentType(isSignUp ? .newPassword : .password)

            if let message = auth.errorMessage {
                errorRow(message)
            }

            PrimaryButton(
                title: auth.isBusy ? "" : (isSignUp ? "Create account" : "Sign in"),
                action: submit
            )
            .overlay { if auth.isBusy { ProgressView().tint(.white) } }
            .disabled(!canSubmit || auth.isBusy)
            .opacity(canSubmit && !auth.isBusy ? 1 : 0.55)
            .padding(.top, 4)

            modeToggle
                .padding(.top, 8)
        }
    }

    private func field(
        _ placeholder: String,
        text: Binding<String>,
        field: Field,
        icon: String,
        secure: Bool = false,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DreamTheme.ink3)
                .frame(width: 20)

            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .font(DreamTheme.Font.text(16))
            .foregroundStyle(DreamTheme.ink)
            .focused($focused, equals: field)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focused == field ? DreamTheme.blue : DreamTheme.line, lineWidth: 1)
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
            Text(message)
                .font(DreamTheme.Font.text(13))
        }
        .foregroundStyle(DreamTheme.error)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            Text(isSignUp ? "Already have an account?" : "New here?")
                .foregroundStyle(DreamTheme.ink2)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    mode = isSignUp ? .signIn : .signUp
                }
            } label: {
                Text(isSignUp ? "Sign in" : "Create an account")
                    .foregroundStyle(DreamTheme.blueDeep)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.plain)
        }
        .font(DreamTheme.Font.text(14))
        .frame(maxWidth: .infinity)
    }

    // MARK: - Email confirmation state

    private var confirmationNotice: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DreamTheme.blueDeep)
            Text("Check your inbox")
                .font(DreamTheme.Font.display(24, weight: .regular))
                .foregroundStyle(DreamTheme.ink)
            Text("We sent a confirmation link to **\(email)**. Tap it to finish creating your account, then come back and sign in.")
                .font(DreamTheme.Font.text(15))
                .foregroundStyle(DreamTheme.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            PrimaryButton(title: "Back to sign in") {
                auth.awaitingEmailConfirmation = false
                mode = .signIn
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    // MARK: - Actions

    private func submit() {
        guard canSubmit, !auth.isBusy else { return }
        focused = nil
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
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DreamTheme.ink2)
                    .frame(width: 38, height: 38)
                    .background(.white, in: Circle())
                    .overlay { Circle().stroke(DreamTheme.line, lineWidth: 1) }
            }
            .accessibilityLabel("Close")
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

#Preview {
    AuthScreen()
}
