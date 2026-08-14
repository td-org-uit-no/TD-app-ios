import SwiftUI

/// Registers a new member via `POST /api/member/`, then signs them in.
///
/// The backend creates the account as `unconfirmed` and mails a confirmation
/// link; following that link is what promotes the account to a full `member`.
/// The user is signed in regardless, so the app is usable straight away — the
/// closing note explains what is still pending rather than blocking on it.
///
/// Fields, order and validation mirror the website's `RegisterForm.tsx`:
/// Fornavn, Etternavn, E-post, Passord, Studiestart, Telefon, then the
/// "Uteksaminert" toggle. The API takes a single `realName`, so the two name
/// boxes are joined on submit exactly as the site does it.
///
/// Client-side checks mirror the site's `validators.ts` and the server's
/// `validate_password` so mistakes surface as the user types rather than after
/// a round trip. The server stays the authority; this is only faster feedback.
struct SignUpView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var classof = ""
    @State private var phone = ""
    @State private var graduated = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case firstName, lastName, email, password, classof, phone }

    // MARK: - Validation

    private var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var trimmedClassof: String {
        classof.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedPhone: String {
        phone.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The site's `nameValidator`: letters in any language, with `-`, `'` and
    /// spaces only *between* letters, max 30 characters.
    private func isNameValid(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 30 else { return false }
        return name.range(
            of: #"^\p{L}+(?:[\s'-]\p{L}+)*$"#,
            options: .regularExpression
        ) != nil
    }

    private var isEmailValid: Bool { trimmedEmail.looksLikeEmail }

    /// The site's `classOfValidator`: four digits, no earlier than 1968 and no
    /// later than the current year.
    private var isClassofValid: Bool {
        guard trimmedClassof.count == 4,
              let year = Int(trimmedClassof) else { return false }
        return year >= 1968 && year <= Calendar.current.component(.year, from: .now)
    }

    /// Phone is the one optional field. The site assumes Norwegian numbers:
    /// exactly eight digits, nothing else.
    private var isPhoneValid: Bool {
        trimmedPhone.isEmpty
            || (trimmedPhone.count == 8 && trimmedPhone.allSatisfy(\.isNumber))
    }

    private var unmetRules: [PasswordRule] {
        PasswordRule.allCases.filter { !$0.isSatisfied(by: password) }
    }

    private var canSubmit: Bool {
        isNameValid(trimmedFirstName)
            && isNameValid(trimmedLastName)
            && isEmailValid
            && unmetRules.isEmpty
            && isClassofValid
            && isPhoneValid
            && !session.isWorking
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                TDScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        // Same wordmark treatment as `LoginView`. The stack is
                        // left-aligned for the form, so the logo and its caption
                        // are centred in a full-width frame of their own.
                        VStack(spacing: 20) {
                            Image(TD.Asset.fullLogo)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 220)
                                .padding(.top, 24)

                            Text("Opprett en TD-konto for å melde deg på arrangementer.")
                                .font(TD.Font.body())
                                .foregroundStyle(TD.inactiveLabel)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)

                        field(
                            "Fornavn",
                            text: $firstName,
                            focus: .firstName,
                            next: .lastName,
                            hint: firstName.isEmpty || isNameValid(trimmedFirstName)
                                ? nil
                                : "Kun bokstaver, maks 30 tegn."
                        )
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)

                        field(
                            "Etternavn",
                            text: $lastName,
                            focus: .lastName,
                            next: .email,
                            hint: lastName.isEmpty || isNameValid(trimmedLastName)
                                ? nil
                                : "Kun bokstaver, maks 30 tegn."
                        )
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)

                        field(
                            "E-post",
                            text: $email,
                            focus: .email,
                            next: .password,
                            hint: email.isEmpty || isEmailValid
                                ? nil
                                : "Skriv inn en gyldig e-postadresse."
                        )
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        field(
                            "Passord",
                            text: $password,
                            focus: .password,
                            next: .classof,
                            isSecure: true
                        )
                        .textContentType(.newPassword)

                        requirements

                        field(
                            "Studiestart",
                            text: $classof,
                            focus: .classof,
                            next: .phone,
                            hint: classof.isEmpty || isClassofValid
                                ? nil
                                : "Studiestart er et årstall, f.eks. 2024."
                        )
                        .keyboardType(.numberPad)

                        field(
                            "Telefon (valgfritt)",
                            text: $phone,
                            focus: .phone,
                            next: nil,
                            hint: isPhoneValid
                                ? nil
                                : "Telefonnummeret må være åtte siffer."
                        )
                        .textContentType(.telephoneNumber)
                        .keyboardType(.numberPad)

                        Toggle(isOn: $graduated) {
                            Text("Uteksaminert")
                                .font(TD.Font.body())
                                .foregroundStyle(TD.primary)
                        }
                        .tint(TD.activeLabel)
                        .padding(.top, 6)

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
                                Text("Bli medlem")
                            }
                        }
                        .buttonStyle(TDButtonStyle())
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.6)
                        .padding(.top, 6)

                        // Set expectations before they submit: the account works
                        // right away, but stays `unconfirmed` until the link is
                        // followed.
                        Text("Du får en e-post med en bekreftelseslenke. Kontoen din er ubekreftet til du har åpnet den.")
                            .font(TD.Font.small())
                            .foregroundStyle(TD.inactiveLabel)
                            .padding(.top, 2)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Bli medlem")
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
            .onAppear { focus = .firstName }
        }
        .tint(TD.red)
    }

    /// The checklist stays visible while typing so the rules read as a goal
    /// rather than as errors, and collapses once every rule passes.
    @ViewBuilder
    private var requirements: some View {
        if !password.isEmpty, !unmetRules.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(PasswordRule.allCases, id: \.self) { rule in
                    let satisfied = rule.isSatisfied(by: password)
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

    /// One input. The name doubles as the box's placeholder, so there is no
    /// separate label above it.
    private func field(
        _ title: String,
        text: Binding<String>,
        focus targetFocus: Field,
        next: Field?,
        isSecure: Bool = false,
        hint: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TDTextField(
                title: title,
                text: text,
                isSecure: isSecure,
                isFocused: focus == targetFocus
            )
            .focused($focus, equals: targetFocus)
            .submitLabel(next == nil ? .go : .next)
            .onSubmit {
                if let next {
                    focus = next
                } else if canSubmit {
                    Task { await submit() }
                }
            }

            if let hint {
                Text(hint)
                    .font(TD.Font.small())
                    .foregroundStyle(TD.warning)
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        do {
            try await session.register(
                MemberInput(
                    // The API stores one name; the site joins the two boxes
                    // with a space, so the same account looks identical
                    // whichever client created it.
                    realName: "\(trimmedFirstName) \(trimmedLastName)",
                    email: trimmedEmail,
                    password: password,
                    classof: trimmedClassof,
                    graduated: graduated,
                    // An empty box means "not given" — the field is optional
                    // server-side, so send null rather than "".
                    phone: trimmedPhone.isEmpty ? nil : trimmedPhone
                )
            )
            dismiss()
        } catch {
            errorMessage = message(for: error)
        }
    }

    /// The API's messages here are English; translate the ones the user can
    /// actually trigger (taken e-mail, weak password).
    private func message(for error: Error) -> String {
        let fallback = "Kunne ikke opprette kontoen."
        guard let apiError = error as? APIError else { return fallback }

        if case let .server(status, _) = apiError {
            switch status {
            case 409: return "E-postadressen er allerede i bruk."
            case 400: return "Passordet er ikke sterkt nok."
            case 422: return "Noen av opplysningene er ugyldige."
            default: break
            }
        }
        return apiError.errorDescription ?? fallback
    }
}
