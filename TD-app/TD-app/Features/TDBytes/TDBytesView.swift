import SwiftUI

/// The kiosk page, ported from the website's `pages/TDBytes/TDBytes.tsx`.
///
/// The site lays its three blocks out side-by-side on desktop; a phone is the
/// site's own `base` breakpoint, where every one of those flexes is already
/// `direction="column"`, so this is the same page stacked the same way.
struct TDBytesView: View {
    @Environment(SessionStore.self) private var session
    @State private var showingLogin = false

    private var isKioskAdmin: Bool {
        guard let role = session.member?.role else { return false }
        return role == .admin || role == .kioskAdmin
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                TDScreenBackground()

                VStack(spacing: 0) {
                    TDPageHeader("TD Bytes")

                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            intro
                            vippsCard
                            locationSection
                            SuggestionCard(showingLogin: $showingLogin)

                            if isKioskAdmin {
                                NavigationLink(value: SuggestionsRoute()) {
                                    Label("Gå til forslagsoversikt", systemImage: "list.bullet.rectangle")
                                        .font(TD.Font.body().weight(.semibold))
                                        .foregroundStyle(TD.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            // The bar stays hidden: `TDPageHeader` names the page as ordinary
            // content. `KioskSuggestionsView` draws its own when pushed.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SuggestionsRoute.self) { _ in
                KioskSuggestionsView()
            }
        }
        .tint(TD.red)
        .sheet(isPresented: $showingLogin) { LoginView() }
    }

    /// The site underlines its heading in TD red. The name itself now lives in
    /// the page header, so only the rule stays here, marking where the page's
    /// own content begins.
    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                """
                Velkommen til TD bytes, TD sin kiosk på campus! Her selger vi \
                diverse snacks, databrus og micro-mat til innkjøpspris. Sitter du \
                og grinder med en oblig og trenger en boost, har glemt matpakka \
                hjemme eller bare får lyst på en cola, stikk innom og sjekk den \
                ut! Kiosken har selvbetjening med Vipps.
                """
            )
            .font(TD.Font.body())
            .foregroundStyle(TD.cardTitle)
        }
    }

    private var vippsCard: some View {
        TDCard {
            VStack(spacing: 14) {
                // The QR is dark-on-light, so it keeps its own white plate
                // rather than sitting on the card's dark surface — scanners
                // need the contrast the code was generated with.
                Image(TD.Asset.tdBytesQR)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: TD.Radius.image))

                Text("Scann QR-koden for å sjekke ut prislistene våre på vipps!")
                    .font(TD.Font.body())
                    .foregroundStyle(TD.cardTitle)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The map is a light-grey campus plan; on the dark page it needs a
            // surface of its own or it reads as a floating white rectangle.
            Image(TD.Asset.tdBytesLocation)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: TD.Radius.image))
                .frame(maxWidth: .infinity)

            Text("Kiosken ligger på TD-kontoret...")
                .font(TD.Font.heading())
                .foregroundStyle(TD.primary)

            Text(
                """
                ...som du finner på A023 i IFI-kjelleren! I tillegg til kiosk \
                finner du også en sofa å deise ned i og en TV å streame noe \
                lættis på.
                """
            )
            .font(TD.Font.body())
            .foregroundStyle(TD.cardTitle)

            Text(
                """
                Kontoret skal være åpent for alle studenter ved IFI, på lik linje \
                med labene. Swipe deg inn med studentkortet og ta deg en kikk!
                """
            )
            .font(TD.Font.body())
            .foregroundStyle(TD.cardTitle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TD.offBackground, in: RoundedRectangle(cornerRadius: TD.Radius.card))
    }
}

/// Marks the push to the admin-only suggestion list. A dedicated type keeps
/// this destination from colliding with the `Event`/`Job` values other stacks
/// push.
private struct SuggestionsRoute: Hashable {}

// MARK: - Suggestion form

/// The site's "Har du et forslag?" card.
struct SuggestionCard: View {
    @Environment(SessionStore.self) private var session
    @Binding var showingLogin: Bool

    @State private var suggestion = ""
    @State private var isSending = false
    @State private var banner: Banner?
    @FocusState private var isFocused: Bool

    struct Banner: Equatable {
        let text: String
        let isError: Bool
    }

    private var trimmed: String {
        suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        TDCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Har du et forslag?")
                    .font(TD.Font.heading())
                    .foregroundStyle(TD.primary)

                Text(
                    """
                    Vi er alltid ute etter å ha ta inn varer som treffer flest \
                    mulig informatikkstudenter. Har du en ide til neste innkjøp, \
                    så fyr inn et forslag her!
                    """
                )
                .font(TD.Font.body())
                .foregroundStyle(TD.cardTitle)

                Divider().overlay(TD.inputBorder)

                if session.isSignedIn {
                    form
                } else {
                    signedOut
                }

                if let banner {
                    Label(
                        banner.text,
                        systemImage: banner.isError
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(TD.Font.subtitle())
                    .foregroundStyle(banner.isError ? TD.error : TD.success)
                }
            }
            .padding(16)
        }
        // A logout while the card is on screen would otherwise leave the
        // previous member's draft and result banner sitting in the form.
        .onChange(of: session.isSignedIn) {
            suggestion = ""
            banner = nil
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Forslag")
                .font(TD.Font.small())
                .foregroundStyle(TD.inactiveLabel)

            TextField("", text: $suggestion, prompt: Text("F.eks. Monster Ultra"))
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .focused($isFocused)
                .onSubmit { send() }
                .font(TD.Font.body())
                .foregroundStyle(TD.primary)
                .padding(10)
                .background(
                    TD.inputBackground,
                    in: RoundedRectangle(cornerRadius: TD.Radius.input)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TD.Radius.input)
                        .strokeBorder(isFocused ? TD.activeLabel : TD.inputBorder, lineWidth: 1)
                )

            Button {
                send()
            } label: {
                if isSending {
                    ProgressView().tint(TD.secondary)
                } else {
                    Text("Send inn")
                }
            }
            .buttonStyle(TDButtonStyle())
            .disabled(isSending || trimmed.isEmpty)
            .opacity(trimmed.isEmpty ? 0.5 : 1)
        }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logg inn for å sende inn forslag")
                .font(TD.Font.body())
                .foregroundStyle(TD.cardTitle)
            Button("Logg inn") { showingLogin = true }
                .buttonStyle(TDButtonStyle())
        }
    }

    private func send() {
        let product = trimmed
        guard !product.isEmpty, !isSending else { return }

        isFocused = false
        isSending = true
        banner = nil

        Task {
            defer { isSending = false }
            do {
                try await APIClient.shared.suggestProduct(product)
                suggestion = ""
                banner = Banner(text: "Forslag ble sendt inn", isError: false)
            } catch {
                banner = Banner(
                    text: (error as? APIError)?.errorDescription
                        ?? "En ukjent feil skjedde",
                    isError: true
                )
            }
        }
    }
}

#Preview {
    TDBytesView()
        .environment(SessionStore())
}
