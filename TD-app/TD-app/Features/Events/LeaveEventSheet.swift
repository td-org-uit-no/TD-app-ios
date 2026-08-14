import SwiftUI
import UIKit

/// Cancellation confirmation, with the website's copy (`EventButton.tsx`)
/// rather than a system action sheet.
///
/// Presented without a background so the content floats over the event page.
///
/// The late-cancellation copy is long and carries a real consequence, so it
/// needs room to breathe and the penalty clause needs emphasis — the site
/// underlines it in `#b73653`. An action sheet renders all of that as small
/// flat grey text, which buries the warning.
struct LeaveEventSheet: View {
    let event: Event
    /// True when the event starts within 24 hours, matching the site's
    /// `valid_cancellation` threshold.
    let isLate: Bool
    let onConfirm: () async -> String?

    @Environment(\.dismiss) private var dismiss

    @State private var isWorking = false
    @State private var errorMessage: String?

    /// The underline colour the site uses for the penalty clause.
    private static let penaltyUnderline = Color(hex: 0xB73653)

    /// The late-cancellation copy, with the penalty clause underlined in the
    /// site's red. Built as one `AttributedString` rather than concatenated
    /// `Text` values, whose `+` is deprecated as of iOS 26.
    private static let lateWarningText: AttributedString = {
        var text = AttributedString(
            "Arrangementet begynner om under 24 timer, og avmelding så nærme arrangement start vil medføre "
        )

        var penalty = AttributedString("en merknad hvis du har mottatt bekreftelse om plass")
        // Attributes are qualified by scope. SwiftUI's carries the style and
        // text colour; `underlineColor` exists only in the UIKit scope, which
        // takes a `UIColor`.
        penalty.swiftUI.underlineStyle = .single
        penalty.swiftUI.foregroundColor = TD.primary
        penalty.uiKit.underlineColor = UIColor(penaltyUnderline)
        text.append(penalty)

        text.append(AttributedString(
            ". To eller flere merknader vil gi nedsatt prioritet på andre arrangementer ut semesteret."
        ))
        return text
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .padding(.horizontal, 20)
        .presentationBackground(.clear)
        .presentationDetents([.height(isLate ? 420 : 260)])
    }

    private var header: some View {
        // 50px tall, centred, 18px/500 — per `.modalHeader` / `.headingBox`.
        Text("Er du sikker på at vil melde deg av?")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(TD.primary)
            .multilineTextAlignment(.center)
            .padding(10)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    private var content: some View {
        VStack(spacing: 18) {
            if isLate {
                lateWarning
            } else {
                Text("Hvis du melder deg av vil du miste plassen din i køen!")
                    .font(TD.Font.body())
                    .foregroundStyle(TD.cardTitle)
                    .multilineTextAlignment(.center)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(TD.Font.subtitle())
                    .foregroundStyle(TD.error)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button {
                    Task { await confirm() }
                } label: {
                    if isWorking {
                        ProgressView().tint(TD.secondary)
                    } else {
                        Text("Bekreft")
                    }
                }
                .buttonStyle(TDButtonStyle(variant: .secondary))
                .disabled(isWorking)

                Button("Avbryt") { dismiss() }
                    .buttonStyle(TDButtonStyle(variant: .primary))
                    .disabled(isWorking)
            }
        }
        .padding(20)
    }

    /// The site's late-cancellation text, with the penalty clause underlined in
    /// red and the host's address offered as a contact.
    private var lateWarning: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(TD.warning)

            Text(Self.lateWarningText)
            .font(TD.Font.body())
            .foregroundStyle(TD.cardTitle)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            if let host = event.host {
                Text("Har du gyldig grunn, ta kontakt med \(host)")
                    .font(TD.Font.subtitle())
                    .foregroundStyle(TD.inactiveLabel)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func confirm() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        if let error = await onConfirm() {
            errorMessage = error
        } else {
            dismiss()
        }
    }
}
