import SwiftUI

/// Edits the fields `PUT /api/member/` accepts: name, e-mail, class year and
/// phone.
///
/// Two backend quirks shape this screen:
///
/// - `update_member` skips falsy values, so a field cannot be blanked out once
///   set. Clearing the phone box therefore leaves the stored number untouched;
///   the form treats an emptied field as "no change" rather than pretending it
///   worked.
/// - Only fields the user actually touched are sent, which keeps the request
///   minimal and avoids re-submitting an unchanged e-mail (the column the
///   backend is most likely to grow a uniqueness check on).
struct EditProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    let member: Member

    @State private var realName: String
    @State private var email: String
    @State private var classof: String
    @State private var phone: String
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case name, email, classof, phone }

    init(member: Member) {
        self.member = member
        _realName = State(initialValue: member.realName)
        _email = State(initialValue: member.email)
        _classof = State(initialValue: member.classof)
        _phone = State(initialValue: member.phone ?? "")
    }

    // MARK: - Validation

    private var trimmedName: String {
        realName.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var isEmailValid: Bool { trimmedEmail.looksLikeEmail }

    /// The API stores `classof` as a free-form string, but the site only ever
    /// writes a four-digit year, so hold new input to that.
    private var isClassofValid: Bool {
        trimmedClassof.count == 4 && trimmedClassof.allSatisfy(\.isNumber)
    }

    private var isPhoneValid: Bool {
        if trimmedPhone.isEmpty { return true }
        let digits = trimmedPhone.filter(\.isNumber)
        return digits.count >= 8 && trimmedPhone.allSatisfy {
            $0.isNumber || $0 == "+" || $0 == " "
        }
    }

    /// Only the fields that differ from what's already stored.
    private var pendingUpdate: MemberUpdate {
        MemberUpdate(
            realName: trimmedName == member.realName ? nil : trimmedName,
            email: trimmedEmail == member.email ? nil : trimmedEmail,
            classof: trimmedClassof == member.classof ? nil : trimmedClassof,
            // An emptied box is "leave it alone", since the API can't clear it.
            phone: trimmedPhone.isEmpty || trimmedPhone == member.phone
                ? nil
                : trimmedPhone
        )
    }

    private var hasChanges: Bool { !pendingUpdate.isEmpty }

    private var canSave: Bool {
        hasChanges
            && !trimmedName.isEmpty
            && isEmailValid
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
                    VStack(alignment: .leading, spacing: 18) {
                        field(
                            "Navn",
                            text: $realName,
                            focus: .name,
                            hint: trimmedName.isEmpty ? "Navn kan ikke være tomt." : nil
                        )
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)

                        field(
                            "E-post",
                            text: $email,
                            focus: .email,
                            hint: isEmailValid ? nil : "Skriv inn en gyldig e-postadresse."
                        )
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        field(
                            "Kull",
                            text: $classof,
                            focus: .classof,
                            hint: isClassofValid ? nil : "Kull er et årstall, f.eks. 2024."
                        )
                        .keyboardType(.numberPad)

                        field(
                            "Telefon",
                            text: $phone,
                            focus: .phone,
                            hint: isPhoneValid ? nil : "Skriv inn et gyldig telefonnummer."
                        )
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)

                        // The API ignores empty values, so the number can be
                        // changed here but not removed.
                        if member.phone != nil {
                            Text("Telefonnummeret kan endres, men ikke fjernes i appen.")
                                .font(TD.Font.small())
                                .foregroundStyle(TD.inactiveLabel)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(TD.Font.subtitle())
                                .foregroundStyle(TD.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await save() }
                        } label: {
                            if session.isWorking {
                                ProgressView().tint(TD.primary)
                            } else {
                                Text("Lagre")
                            }
                        }
                        .buttonStyle(TDButtonStyle())
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.6)
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Rediger profil")
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
            .onAppear { focus = .name }
        }
        .tint(TD.red)
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        focus field: Field,
        hint: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TD.Font.subtitle())
                .foregroundStyle(TD.inactiveLabel)

            TDTextField(title: title, text: text, isFocused: focus == field)
                .focused($focus, equals: field)

            // Only nag once there's something to correct — an untouched field
            // shouldn't come up red.
            if let hint, !text.wrappedValue.isEmpty {
                Text(hint)
                    .font(TD.Font.small())
                    .foregroundStyle(TD.warning)
            }
        }
    }

    private func save() async {
        errorMessage = nil
        let update = pendingUpdate
        guard !update.isEmpty else { dismiss(); return }

        do {
            try await session.updateMember(update)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
                ?? "Kunne ikke lagre endringene."
        }
    }
}
