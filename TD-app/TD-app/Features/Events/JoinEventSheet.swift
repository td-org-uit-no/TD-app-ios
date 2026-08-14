import SwiftUI

/// Collects the same signup preferences the website asks for before joining.
///
/// The backend stores `food`, `transportation` and `dietaryRestrictions` on the
/// participant record and organisers read them off the attendee list, so these
/// must come from the user rather than being defaulted.
struct JoinEventSheet: View {
    let event: Event
    /// Called with the chosen options; returns an error message on failure.
    let onSubmit: (JoinEventPayload) async -> String?

    @Environment(\.dismiss) private var dismiss

    @State private var wantsFood = false
    @State private var wantsTransport = false
    @State private var dietaryRestrictions = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var dietFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                TDScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(event.title)
                            .font(TD.Font.heading())
                            .foregroundStyle(TD.primary)

                        if event.bindingRegistration {
                            Label(
                                "Påmeldingen er bindende.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(TD.Font.subtitle())
                            .foregroundStyle(TD.warning)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                TD.warning.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: TD.Radius.input)
                            )
                        }

                        // Only ask about what this event actually offers — the
                        // API expects null for options the event doesn't have.
                        if event.food {
                            toggleRow(
                                title: "Jeg vil ha mat",
                                subtitle: "Arrangementet serverer mat",
                                isOn: $wantsFood
                            )

                            if wantsFood {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Allergier eller matpreferanser")
                                        .font(TD.Font.subtitle())
                                        .foregroundStyle(TD.inactiveLabel)
                                    TDTextField(
                                        title: "F.eks. vegetar, nøtteallergi",
                                        text: $dietaryRestrictions,
                                        isFocused: dietFocused
                                    )
                                    .focused($dietFocused)
                                }
                            }
                        }

                        if event.transportation {
                            toggleRow(
                                title: "Jeg trenger transport",
                                subtitle: "Arrangementet tilbyr transport",
                                isOn: $wantsTransport
                            )
                        }

                        if !event.food, !event.transportation {
                            Text("Dette arrangementet har ingen valg — trykk meld deg på for å bli med.")
                                .font(TD.Font.body())
                                .foregroundStyle(TD.inactiveLabel)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(TD.Font.subtitle())
                                .foregroundStyle(TD.error)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            if isSubmitting {
                                ProgressView().tint(TD.secondary)
                            } else {
                                // Matches the website's preferences modal.
                                Text("Meld på")
                            }
                        }
                        .buttonStyle(TDButtonStyle(variant: .secondary))
                        .disabled(isSubmitting)
                        .padding(.top, 4)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Påmelding")
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
        }
        .tint(TD.red)
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TD.Font.body())
                    .foregroundStyle(TD.primary)
                Text(subtitle)
                    .font(TD.Font.small())
                    .foregroundStyle(TD.inactiveLabel)
            }
        }
        .tint(TD.red)
        .padding(14)
        .background(TD.surface, in: RoundedRectangle(cornerRadius: TD.Radius.card))
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        // Always send concrete values, never null.
        //
        // `JoinEventPayload` declares these Optional, but `join_event` copies
        // them straight into `Participant`, where `food`/`transportation` are
        // non-optional `bool` and `dietaryRestrictions` a non-optional `str`.
        // Sending null therefore fails Pydantic validation *after* the request
        // is accepted, and the server returns a 500.
        let payload = JoinEventPayload(
            food: event.food ? wantsFood : false,
            transportation: event.transportation ? wantsTransport : false,
            dietaryRestrictions: wantsFood ? dietaryRestrictions : ""
        )

        if let error = await onSubmit(payload) {
            errorMessage = error
        } else {
            dismiss()
        }
    }
}
