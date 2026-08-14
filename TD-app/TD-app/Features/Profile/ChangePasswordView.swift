import SwiftUI

/// Changes the logged-in member's password via `POST /api/auth/password`.
///
/// The backend validates strength itself and answers 400 with a long English
/// message when it fails. Rather than surface that after a round trip, the
/// same rules are checked here as the user types (`PasswordRule` mirrors the
/// server's regex in `app/utils/validation.py`) — the server stays the
/// authority, this is just faster feedback.
struct ChangePasswordView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case current, new, confirm }

    private var unmetRules: [PasswordRule] {
        PasswordRule.allCases.filter { !$0.isSatisfied(by: newPassword) }
    }

    private var passwordsMatch: Bool {
        !confirmPassword.isEmpty && newPassword == confirmPassword
    }

    /// Changing a password to itself is a no-op the server would accept; catch
    /// it here so the user isn't told "saved" without anything happening.
    private var isReusingCurrent: Bool {
        !newPassword.isEmpty && newPassword == currentPassword
    }

    private var canSubmit: Bool {
        !currentPassword.isEmpty
            && unmetRules.isEmpty
            && passwordsMatch
            && !isReusingCurrent
            && !session.isWorking
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TDScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        labelled("Nåværende passord") {
                            TDTextField(
                                title: "Nåværende passord",
                                text: $currentPassword,
                                isSecure: true,
                                isFocused: focus == .current
                            )
                            .textContentType(.password)
                            .focused($focus, equals: .current)
                            .submitLabel(.next)
                            .onSubmit { focus = .new }
                        }

                        labelled("Nytt passord") {
                            TDTextField(
                                title: "Nytt passord",
                                text: $newPassword,
                                isSecure: true,
                                isFocused: focus == .new
                            )
                            .textContentType(.newPassword)
                            .focused($focus, equals: .new)
                            .submitLabel(.next)
                            .onSubmit { focus = .confirm }
                        }

                        requirements

                        labelled("Bekreft nytt passord") {
                            TDTextField(
                                title: "Bekreft nytt passord",
                                text: $confirmPassword,
                                isSecure: true,
                                isFocused: focus == .confirm
                            )
                            .textContentType(.newPassword)
                            .focused($focus, equals: .confirm)
                            .submitLabel(.go)
                            .onSubmit { if canSubmit { Task { await submit() } } }
                        }

                        if !confirmPassword.isEmpty, !passwordsMatch {
                            hint("Passordene er ikke like.", color: TD.warning)
                        }

                        if isReusingCurrent {
                            hint(
                                "Det nye passordet må være forskjellig fra det nåværende.",
                                color: TD.warning
                            )
                        }

                        if let errorMessage {
                            hint(errorMessage, color: TD.error)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            if session.isWorking {
                                ProgressView().tint(TD.primary)
                            } else {
                                Text("Endre passord")
                            }
                        }
                        .buttonStyle(TDButtonStyle())
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.6)
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Endre passord")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(TD.offBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                        .foregroundStyle(TD.inactiveLabel)
                }
            }
            .onAppear { focus = .current }
        }
        .tint(TD.red)
    }

    /// The checklist stays visible while typing so the rules read as a goal
    /// rather than as errors, and collapses once every rule passes.
    @ViewBuilder
    private var requirements: some View {
        if !newPassword.isEmpty, !unmetRules.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(PasswordRule.allCases, id: \.self) { rule in
                    let satisfied = rule.isSatisfied(by: newPassword)
                    HStack(spacing: 7) {
                        Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(satisfied ? TD.success : TD.inactiveLabel)
                        Text(rule.label)
                            .foregroundStyle(satisfied ? TD.cardSubtitle : TD.inactiveLabel)
                    }
                    .font(TD.Font.small())
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                TD.inputBackground,
                in: RoundedRectangle(cornerRadius: TD.Radius.input)
            )
        }
    }

    private func labelled(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TD.Font.subtitle())
                .foregroundStyle(TD.inactiveLabel)
            content()
        }
    }

    private func hint(_ text: String, color: Color) -> some View {
        Text(text)
            .font(TD.Font.small())
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() async {
        errorMessage = nil
        do {
            try await session.changePassword(
                current: currentPassword, new: newPassword
            )
            dismiss()
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// The API's own strings are English and, for a wrong password, terse
    /// ("Wrong password"). Translate the two cases the user can actually hit.
    private func message(for error: Error) -> String {
        let fallback = "Kunne ikke endre passordet."
        guard let apiError = error as? APIError else { return fallback }

        if case let .server(status, _) = apiError {
            switch status {
            case 403: return "Feil nåværende passord."
            case 400: return "Det nye passordet er ikke sterkt nok."
            default: break
            }
        }
        return apiError.errorDescription ?? fallback
    }
}

/// The password rules enforced by the API's `validate_password`.
enum PasswordRule: CaseIterable {
    case length
    case lowercase
    case uppercase
    case digit
    case special

    var label: String {
        switch self {
        case .length:    "Minst 8 tegn"
        case .lowercase: "Én liten bokstav"
        case .uppercase: "Én stor bokstav"
        case .digit:     "Ett tall"
        case .special:   "Ett spesialtegn (f.eks. ! ? # %)"
        }
    }

    func isSatisfied(by password: String) -> Bool {
        switch self {
        case .length:
            password.count >= 8
        case .lowercase:
            password.contains { $0.isLowercase }
        case .uppercase:
            password.contains { $0.isUppercase }
        case .digit:
            password.contains { $0.isNumber }
        case .special:
            // The server's character class is the printable ASCII punctuation
            // ranges !-/ :-@ [-` {-~ — anything non-alphanumeric in ASCII.
            password.contains { $0.isASCII && !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
        }
    }
}
