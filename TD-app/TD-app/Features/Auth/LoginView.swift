import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var showingSignUp = false
    @State private var showingForgotPassword = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        email.contains("@") && !password.isEmpty && !session.isWorking
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TDScreenBackground()

                VStack(spacing: 20) {
                    // The site's wordmark; it's red-on-transparent so it reads
                    // correctly against the dark background.
                    Image(TD.Asset.fullLogo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220)
                        .padding(.top, 24)

                    Text("Logg inn med TD-kontoen din")
                        .font(TD.Font.body())
                        .foregroundStyle(TD.inactiveLabel)

                    VStack(spacing: 14) {
                        TDTextField(
                            title: "E-post",
                            text: $email,
                            isFocused: focus == .email
                        )
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }

                        TDTextField(
                            title: "Passord",
                            text: $password,
                            isSecure: true,
                            isFocused: focus == .password
                        )
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { Task { await submit() } } }
                    }

                    if let error = session.loginError {
                        Text(error)
                            .font(TD.Font.subtitle())
                            .foregroundStyle(TD.error)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if session.isWorking {
                            ProgressView().tint(TD.primary)
                        } else {
                            Text("Logg inn")
                        }
                    }
                    .buttonStyle(TDButtonStyle())
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.6)

                    // A text link rather than a third bordered button: it's a
                    // recovery path, and giving it equal weight to the two real
                    // choices would make the screen read as three-way.
                    Button("Glemt passord?") {
                        focus = nil
                        showingForgotPassword = true
                    }
                    .font(TD.Font.subtitle())
                    .foregroundStyle(TD.inactiveLabel)
                    .disabled(session.isWorking)

                    // Separates "I have an account" above from "I don't" below.
                    HStack(spacing: 12) {
                        line
                        Text("eller")
                            .font(TD.Font.small())
                            .foregroundStyle(TD.inactiveLabel)
                        line
                    }
                    .padding(.top, 4)

                    // The `primary` variant is the quieter of the two styles, so
                    // signing up stays clearly available without competing with
                    // the login button.
                    Button("Bli medlem") {
                        focus = nil
                        showingSignUp = true
                    }
                    .buttonStyle(TDButtonStyle(variant: .primary))
                    .disabled(session.isWorking)

                    Spacer()
                }
                .padding(20)
            }
            .sheet(isPresented: $showingSignUp) {
                // Registering signs the user straight in, which leaves this
                // sheet stranded behind the dismissed one — close it too.
                if session.isSignedIn { dismiss() }
            } content: {
                SignUpView()
            }
            .sheet(isPresented: $showingForgotPassword) {
                // Carry over whatever was typed, so the address isn't retyped.
                ForgotPasswordView(email: email)
            }
            .navigationTitle("Logg inn")
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
            .onAppear { focus = .email }
        }
        .tint(TD.red)
    }

    private var line: some View {
        Rectangle()
            .fill(TD.inputBorder)
            .frame(height: 1)
    }

    private func submit() async {
        await session.logIn(email: email, password: password)
        if session.isSignedIn { dismiss() }
    }
}

/// Text input styled like the site's (`text.scss`): dark fill, 2px border that
/// turns purple on focus, 5px radius.
struct TDTextField: View {
    let title: String
    @Binding var text: String
    var isSecure = false
    var isFocused = false

    var body: some View {
        Group {
            if isSecure {
                SecureField("", text: $text, prompt: prompt)
            } else {
                TextField("", text: $text, prompt: prompt)
            }
        }
        .font(TD.Font.body())
        .foregroundStyle(TD.primary)
        .padding(14)
        .background(TD.inputBackground, in: RoundedRectangle(cornerRadius: TD.Radius.input))
        .overlay(
            RoundedRectangle(cornerRadius: TD.Radius.input)
                .strokeBorder(
                    isFocused ? TD.activeLabel : TD.inputBorder,
                    lineWidth: 2
                )
        )
        .animation(.easeInOut(duration: 0.3), value: isFocused)
    }

    private var prompt: Text {
        Text(title).foregroundColor(TD.inactiveLabel)
    }
}
