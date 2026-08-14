import SwiftUI

/// Requests a password-reset link via `POST /api/member/reset-password/code/{email}`.
///
/// This screen deliberately stops after asking for the mail. The reset code the
/// backend generates is only ever delivered as a *website* link
/// (`FRONTEND_URL/reset-password/{code}`), so there is no bare token for the
/// user to type back into the app — the reset is finished in a browser.
///
/// The backend answers 404 when the address belongs to no member. That is not
/// shown: relaying it would turn this screen into an oracle for which addresses
/// are registered. Every outcome reads the same, which also matches how the
/// success copy is phrased ("hvis adressen er registrert").
struct ForgotPasswordView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// Prefilled from the login form so the user doesn't retype it.
    @State var email: String

    @State private var didSend = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isEmailValid: Bool { trimmedEmail.looksLikeEmail }

    private var canSubmit: Bool { isEmailValid && !session.isWorking }

    var body: some View {
        NavigationStack {
            ZStack {
                TDScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if didSend {
                            confirmation
                        } else {
                            form
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Glemt passord")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(TD.offBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSend ? "Lukk" : "Avbryt") { dismiss() }
                        .foregroundStyle(TD.inactiveLabel)
                }
            }
            .onAppear { isFocused = true }
        }
        .tint(TD.red)
    }

    private var form: some View {
        Group {
            Text("Skriv inn e-postadressen din, så sender vi deg en lenke for å lage et nytt passord.")
                .font(TD.Font.body())
                .foregroundStyle(TD.inactiveLabel)

            VStack(alignment: .leading, spacing: 6) {
                Text("E-post")
                    .font(TD.Font.subtitle())
                    .foregroundStyle(TD.inactiveLabel)

                TDTextField(
                    title: "E-post",
                    text: $email,
                    isFocused: isFocused
                )
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.go)
                .onSubmit { if canSubmit { Task { await submit() } } }

                if !email.isEmpty, !isEmailValid {
                    Text("Skriv inn en gyldig e-postadresse.")
                        .font(TD.Font.small())
                        .foregroundStyle(TD.warning)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(TD.Font.subtitle())
                    .foregroundStyle(TD.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await submit() }
            } label: {
                if session.isWorking {
                    ProgressView().tint(TD.primary)
                } else {
                    Text("Send lenke")
                }
            }
            .buttonStyle(TDButtonStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.6)
            .padding(.top, 4)
        }
    }

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "envelope.badge")
                    .foregroundStyle(TD.success)
                Text("Sjekk e-posten din")
                    .font(TD.Font.cardTitle())
                    .foregroundStyle(TD.primary)
            }

            Text("Hvis \(trimmedEmail) er registrert hos oss, har vi sendt en lenke dit for å lage et nytt passord.")
                .font(TD.Font.body())
                .foregroundStyle(TD.inactiveLabel)

            // The TTL index on `passwordResets` drops the code after 10 minutes,
            // so saying so up front saves a second round trip.
            Text("Lenken åpnes i nettleseren og er gyldig i 10 minutter.")
                .font(TD.Font.small())
                .foregroundStyle(TD.inactiveLabel)

            Button("Ferdig") { dismiss() }
                .buttonStyle(TDButtonStyle())
                .padding(.top, 4)
        }
    }

    private func submit() async {
        errorMessage = nil
        do {
            try await session.requestPasswordReset(email: trimmedEmail)
            didSend = true
        } catch APIError.notFound {
            // No such member. Show the same confirmation as a hit — see the
            // type's documentation for why.
            didSend = true
        } catch {
            // Anything else is a real failure (offline, server down) and is
            // worth telling the user about, since retrying may help.
            errorMessage = (error as? APIError)?.errorDescription
                ?? "Kunne ikke sende lenken. Prøv igjen."
        }
    }
}
