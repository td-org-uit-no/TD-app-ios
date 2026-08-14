import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @State private var showingLogin = false
    @State private var showingSignUp = false
    @State private var showingEditProfile = false
    @State private var showingChangePassword = false
    @State private var showingAdmin = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                TDScreenBackground()

                VStack(spacing: 0) {
                    TDPageHeader("Profil")

                    if let member = session.member {
                        signedInContent(member)
                    } else {
                        // Centred in what's left below the header, rather than
                        // pinned under it.
                        signedOutContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            // The bar stays hidden: `TDPageHeader` names the page as ordinary
            // content. Pushed screens draw their own header with a back button.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingAdmin) { AdminView() }
        }
        .tint(TD.red)
        .sheet(isPresented: $showingLogin) { LoginView() }
        .sheet(isPresented: $showingSignUp) { SignUpView() }
        .sheet(isPresented: $showingEditProfile) {
            if let member = session.member {
                // Keyed on the member so a re-opened sheet starts from the
                // freshly saved values rather than a stale `init` snapshot.
                EditProfileView(member: member)
                    .id(member)
            }
        }
        .sheet(isPresented: $showingChangePassword) { ChangePasswordView() }
    }

    private func signedInContent(_ member: Member) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if member.penalty > 0 {
                    penaltyBanner(member.penalty)
                }

                detailsSection(member)

                if member.isAdmin {
                    adminSection
                }

                accountSection
            }
            .padding(.vertical, 12)
        }
        .refreshable { await session.refreshMember() }
    }

    /// The stored details, with the edit entry point.
    ///
    /// Role, status and `graduated` are shown but not editable: `PUT
    /// /api/member/` accepts none of them (role and status are admin-only, and
    /// nothing in the API flips `graduated`), so offering them as editable
    /// fields would be a lie.
    private func detailsSection(_ member: Member) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mine opplysninger")
                    .font(TD.Font.heading())
                    .foregroundStyle(TD.primary)

                Spacer(minLength: 8)

                Button("Rediger") { showingEditProfile = true }
                    .font(TD.Font.subtitle())
                    .foregroundStyle(TD.secondary)
            }

            TDCard {
                VStack(spacing: 0) {
                    detailRow("Navn", member.realName, icon: "person")
                    divider
                    detailRow("E-post", member.email, icon: "envelope")
                    divider
                    detailRow("Kull", member.classof, icon: "graduationcap")
                    divider
                    detailRow(
                        "Telefon",
                        member.phone?.isEmpty == false ? member.phone! : "Ikke oppgitt",
                        icon: "phone",
                        isPlaceholder: member.phone?.isEmpty != false
                    )
                    divider
                    detailRow(
                        "Rolle",
                        member.role.rawValue.capitalized,
                        icon: "person.badge.key"
                    )
                    divider
                    detailRow(
                        "Status",
                        member.status == .active ? "Aktiv" : "Inaktiv",
                        icon: "checkmark.seal"
                    )
                    if member.graduated {
                        divider
                        detailRow("Uteksaminert", "Ja", icon: "checkmark.circle")
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
    }

    private func detailRow(
        _ label: String,
        _ value: String,
        icon: String,
        isPlaceholder: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(TD.inactiveLabel)
                .frame(width: 20)

            Text(label)
                .font(TD.Font.subtitle())
                .foregroundStyle(TD.inactiveLabel)

            Spacer(minLength: 12)

            Text(value)
                .font(TD.Font.body())
                .foregroundStyle(isPlaceholder ? TD.inactiveLabel : TD.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var divider: some View {
        Rectangle()
            .fill(TD.inputBorder)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    /// Entry point to the admin area, mirroring the website's admin nav item.
    /// Only rendered for admins; the endpoints behind it are admin-gated too,
    /// so this is a convenience rather than the access control itself.
    private var adminSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Administrasjon")
                .font(TD.Font.heading())
                .foregroundStyle(TD.primary)

            Button {
                showingAdmin = true
            } label: {
                TDCard {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 15))
                            .foregroundStyle(TD.red)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Adminpanel")
                                .font(TD.Font.body())
                                .foregroundStyle(TD.primary)
                            Text("Statistikk, medlemmer og arrangementer")
                                .font(TD.Font.small())
                                .foregroundStyle(TD.inactiveLabel)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(TD.inactiveLabel)
                    }
                    .padding(14)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Konto")
                .font(TD.Font.heading())
                .foregroundStyle(TD.primary)

            Button("Endre passord") { showingChangePassword = true }
                .buttonStyle(TDButtonStyle())

            Button("Logg ut") {
                Task { await session.logOut() }
            }
            .buttonStyle(TDButtonStyle(variant: .primary))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func penaltyBanner(_ penalty: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(
                penalty == 1
                ? "Du har én prikk for sen avmelding."
                : "Du har \(penalty) prikker for sen avmelding."
            )
            .font(TD.Font.subtitle())
        }
        .foregroundStyle(TD.warning)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            TD.warning.opacity(0.15),
            in: RoundedRectangle(cornerRadius: TD.Radius.input)
        )
        .padding(.horizontal, 16)
    }

    private var signedOutContent: some View {
        VStack(spacing: 14) {
            Image(TD.Asset.logo)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .opacity(0.9)
            Text("Ikke logget inn")
                .font(TD.Font.heading())
                .foregroundStyle(TD.primary)
            Text("Logg inn for å melde deg på arrangementer og se profilen din.")
                .font(TD.Font.body())
                .foregroundStyle(TD.inactiveLabel)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                Button("Logg inn") { showingLogin = true }
                    .buttonStyle(TDButtonStyle())

                // The quieter `primary` variant: signing up is a real option
                // here, but logging in is the common case.
                Button("Bli medlem") { showingSignUp = true }
                    .buttonStyle(TDButtonStyle(variant: .primary))
            }
            .frame(maxWidth: 200)
            .padding(.top, 4)
        }
        .padding(32)
    }
}
