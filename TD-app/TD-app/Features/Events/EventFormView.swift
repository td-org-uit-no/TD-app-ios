import PhotosUI
import SwiftUI

/// Creates or edits an event. Admin only.
///
/// The field set mirrors the website's create-event form (`EventForm.tsx`):
/// title, date, time, address, price, max participants, description, an
/// optional registration-opening date/time, four toggles, and a PNG poster.
///
/// One form serves both modes, but they hit different endpoints with different
/// rules:
///
/// - **Create** posts an `EventInput`, where every core field is required, then
///   uploads the poster in a second request against the returned id.
/// - **Edit** sends an `EventUpdate` containing *only* what changed. The
///   backend re-validates the merged event and rejects an update that would
///   clear a required field, so unchanged fields must be omitted rather than
///   re-sent. It also refuses a `date` in the past — including one the event
///   already had — so the date is only included when it was actually edited.
struct EventFormView: View {
    enum Mode {
        case create
        case edit(Event)
    }

    let mode: Mode
    /// Called after a successful write so the caller can reload its list.
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var address: String
    @State private var descriptionText: String
    @State private var priceText: String
    @State private var maxParticipantsText: String
    /// Date and time are held separately to match the website's two inputs,
    /// then combined on save.
    @State private var day: Date
    @State private var time: Date
    @State private var hasRegistrationOpening: Bool
    @State private var registrationDay: Date
    @State private var registrationTime: Date
    @State private var isPublic: Bool
    @State private var bindingRegistration: Bool
    @State private var transportation: Bool
    @State private var food: Bool

    @State private var posterItem: PhotosPickerItem?
    @State private var posterData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: Mode, onSaved: @escaping () async -> Void) {
        self.mode = mode
        self.onSaved = onSaved

        let event: Event? = if case let .edit(existing) = mode { existing } else { nil }
        // A new event defaults to a week out at 18:00 — in the future, which the
        // API requires, and a plausible slot.
        let start = event?.date ?? Self.defaultDate

        _title = State(initialValue: event?.title ?? "")
        _address = State(initialValue: event?.address ?? "")
        _descriptionText = State(initialValue: event?.description ?? "")
        _priceText = State(initialValue: event.map { String($0.price) } ?? "0")
        _maxParticipantsText = State(
            initialValue: event?.maxParticipants.map(String.init) ?? ""
        )
        _day = State(initialValue: start)
        _time = State(initialValue: start)

        let opening = event?.registrationOpeningDate
        _hasRegistrationOpening = State(initialValue: opening != nil)
        _registrationDay = State(initialValue: opening ?? .now)
        _registrationTime = State(initialValue: opening ?? .now)

        // The website defaults a new event to *not* public, warning that it
        // stays admin-only until ticked. Matching that avoids publishing an
        // event by accident.
        _isPublic = State(initialValue: event?.public ?? false)
        _bindingRegistration = State(initialValue: event?.bindingRegistration ?? false)
        _transportation = State(initialValue: event?.transportation ?? false)
        _food = State(initialValue: event?.food ?? false)
    }

    private static var defaultDate: Date {
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        return Calendar.current.date(
            bySettingHour: 18, minute: 0, second: 0, of: nextWeek
        ) ?? nextWeek
    }

    /// Combines a day with a time-of-day into one timestamp.
    private func combine(day: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let timeParts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(
            bySettingHour: timeParts.hour ?? 0,
            minute: timeParts.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }

    private var startDate: Date { combine(day: day, time: time) }

    private var registrationOpeningDate: Date? {
        hasRegistrationOpening
            ? combine(day: registrationDay, time: registrationTime)
            : nil
    }

    private var existingEvent: Event? {
        if case let .edit(event) = mode { return event }
        return nil
    }

    private var isEditing: Bool { existingEvent != nil }

    // MARK: - Validation

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedDescription: String {
        descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var price: Int? { Int(priceText.trimmingCharacters(in: .whitespaces)) }

    /// Empty means "no limit", which the API models as null.
    private var maxParticipants: Int? {
        let trimmed = maxParticipantsText.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private var isMaxParticipantsValid: Bool {
        let trimmed = maxParticipantsText.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || (Int(trimmed).map { $0 > 0 } ?? false)
    }

    /// Only enforced when creating, or when an edit actually moves the date —
    /// an event that has already happened is otherwise left alone.
    private var isDateValid: Bool {
        guard !isEditing || startDate != existingEvent?.date else { return true }
        return startDate > .now
    }

    /// The backend also rejects a registration opening after the event starts.
    private var isRegistrationDateValid: Bool {
        guard let opening = registrationOpeningDate else { return true }
        return opening < startDate
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty
            && !trimmedAddress.isEmpty
            && !trimmedDescription.isEmpty
            && price != nil
            && isMaxParticipantsValid
            && isDateValid
            && isRegistrationDateValid
            && !isSaving
            && (!isEditing || hasChanges)
    }

    private var hasChanges: Bool { !pendingUpdate.isEmpty || posterData != nil }

    /// The diff against the stored event, used in edit mode.
    private var pendingUpdate: EventUpdate {
        guard let event = existingEvent else { return EventUpdate() }

        var update = EventUpdate()
        if trimmedTitle != event.title { update.title = trimmedTitle }
        if trimmedAddress != event.address { update.address = trimmedAddress }
        if trimmedDescription != event.description {
            update.description = trimmedDescription
        }
        if startDate != event.date { update.date = startDate }
        if let price, price != event.price { update.price = price }
        if maxParticipants != event.maxParticipants {
            update.maxParticipants = maxParticipants
        }
        if isPublic != event.public { update.public = isPublic }
        if transportation != event.transportation {
            update.transportation = transportation
        }
        if food != event.food { update.food = food }
        if registrationOpeningDate != event.registrationOpeningDate {
            update.registrationOpeningDate = registrationOpeningDate
        }
        return update
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                TDScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        group("Tittel") {
                            TDTextField(title: "Tittel", text: $title)
                        }

                        group("Dato og tid") {
                            HStack(spacing: 10) {
                                DatePicker(
                                    "", selection: $day,
                                    displayedComponents: .date
                                )
                                .labelsHidden()

                                DatePicker(
                                    "", selection: $time,
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()

                                Spacer(minLength: 0)
                            }
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .tint(TD.red)

                            if !isDateValid {
                                warning("Tidspunktet må være fram i tid.")
                            }
                        }

                        group("Adresse") {
                            TDTextField(title: "Adresse", text: $address)
                        }

                        HStack(spacing: 12) {
                            group("Pris (kr)") {
                                TDTextField(title: "0", text: $priceText)
                                    .keyboardType(.numberPad)
                            }
                            group("Maks antall") {
                                TDTextField(
                                    title: "Valgfritt",
                                    text: $maxParticipantsText
                                )
                                .keyboardType(.numberPad)
                            }
                        }

                        if !isMaxParticipantsValid {
                            warning("Maks antall må være et positivt tall, eller stå tomt.")
                        }

                        group("Beskrivelse") {
                            TDTextEditor(text: $descriptionText)
                        }

                        registrationOpening
                        toggles
                        posterPicker

                        if !isPublic {
                            // The same note the website shows under this toggle.
                            Text("MERK: Arrangementet vil ikke være synlig for andre enn admin.")
                                .font(TD.Font.small())
                                .italic()
                                .foregroundStyle(TD.error)
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
                            if isSaving {
                                ProgressView().tint(TD.primary)
                            } else {
                                Text(isEditing ? "Lagre" : "Opprett")
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
            .navigationTitle(isEditing ? "Rediger arrangement" : "Nytt arrangement")
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
            .task(id: posterItem) { await loadPoster() }
        }
        .tint(TD.red)
    }

    private var registrationOpening: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) {
                tdToggle("Sett når påmeldingen åpner", isOn: $hasRegistrationOpening)

                if hasRegistrationOpening {
                    Divider().overlay(TD.inputBorder)
                    HStack(spacing: 10) {
                        DatePicker(
                            "", selection: $registrationDay,
                            displayedComponents: .date
                        )
                        .labelsHidden()

                        DatePicker(
                            "", selection: $registrationTime,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()

                        Spacer(minLength: 0)
                    }
                    .datePickerStyle(.compact)
                    .colorScheme(.dark)
                    .tint(TD.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
            }
            .background(
                TD.inputBackground,
                in: RoundedRectangle(cornerRadius: TD.Radius.input)
            )

            if !isRegistrationDateValid {
                warning("Påmeldingen må åpne før arrangementet starter.")
            }
        }
    }

    private var toggles: some View {
        VStack(spacing: 0) {
            tdToggle("Servering av mat", isOn: $food)
            Divider().overlay(TD.inputBorder)
            tdToggle("Mulighet for transport", isOn: $transportation)
            Divider().overlay(TD.inputBorder)
            tdToggle("Offentlig (synlig for vanlige brukere)", isOn: $isPublic)
            Divider().overlay(TD.inputBorder)
            tdToggle("Bindende påmelding", isOn: $bindingRegistration)
                // Creation-only: `EventUpdate` has no such field, so an edit
                // can't change it.
                .disabled(isEditing)
                .opacity(isEditing ? 0.5 : 1)
        }
        .background(TD.inputBackground, in: RoundedRectangle(cornerRadius: TD.Radius.input))
    }

    /// PNG only, matching the website's file selector — the backend saves
    /// whatever it receives as `.png` regardless of the real format.
    private var posterPicker: some View {
        // Read out of `@State` here, in the isolated body, rather than inside
        // the picker's `@Sendable` label closure below. `Binding` is itself
        // `Sendable`, so the closure captures it without a data-race warning.
        let poster = $posterData

        return VStack(alignment: .leading, spacing: 8) {
            Text("Bilde")
                .font(TD.Font.subtitle())
                .foregroundStyle(TD.inactiveLabel)

            PhotosPicker(selection: $posterItem, matching: .images) {
                TDImagePickerLabel(
                    data: poster,
                    placeholderIcon: "photo",
                    emptyTitle: "Last opp bilde til arrangementet",
                    selectedTitle: "Bilde valgt — trykk for å bytte",
                    onClear: { posterItem = nil }
                )
            }
        }
    }

    private func tdToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(TD.Font.body())
                .foregroundStyle(TD.cardTitle)
        }
        .tint(TD.red)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func warning(_ text: String) -> some View {
        Text(text)
            .font(TD.Font.small())
            .foregroundStyle(TD.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func group(
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

    // MARK: - Saving

    /// Re-encodes the picked image as PNG. The backend always writes the upload
    /// to a `.png` path, so handing it a HEIC or JPEG would store a file whose
    /// extension lies about its contents.
    private func loadPoster() async {
        guard let posterItem else { return }
        guard
            let data = try? await posterItem.loadTransferable(type: Data.self),
            let image = UIImage(data: data),
            let png = image.pngData()
        else {
            errorMessage = "Kunne ikke lese bildet."
            return
        }
        posterData = png
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            if let event = existingEvent {
                let update = pendingUpdate
                if !update.isEmpty {
                    try await APIClient.shared.updateEvent(id: event.eid, update: update)
                }
                if let posterData {
                    try await APIClient.shared.uploadEventImage(
                        id: event.eid, pngData: posterData
                    )
                    // The poster URL doesn't change when the image does, so the
                    // cached copy has to be dropped explicitly.
                    ImageStore.shared.invalidateAll()
                }
            } else {
                let id = try await APIClient.shared.createEvent(makeInput())
                if let posterData {
                    // The event exists at this point, so a failed image upload
                    // is reported without discarding the event itself.
                    do {
                        try await APIClient.shared.uploadEventImage(
                            id: id, pngData: posterData
                        )
                        ImageStore.shared.invalidateAll()
                    } catch {
                        await onSaved()
                        errorMessage = """
                            Arrangementet ble opprettet, men bildet ble ikke lastet opp. \
                            Rediger arrangementet for å prøve igjen.
                            """
                        return
                    }
                }
            }
            await onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
                ?? "Kunne ikke lagre arrangementet."
        }
    }

    private func makeInput() -> EventInput {
        EventInput(
            title: trimmedTitle,
            date: startDate,
            address: trimmedAddress,
            price: price ?? 0,
            description: trimmedDescription,
            public: isPublic,
            bindingRegistration: bindingRegistration,
            transportation: transportation,
            food: food,
            maxParticipants: maxParticipants,
            registrationOpeningDate: registrationOpeningDate
        )
    }
}

/// A multi-line input styled to match `TDTextField`.
///
/// `TextEditor` draws its own opaque background, which has to be hidden before
/// the TD fill shows through.
struct TDTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 120

    var body: some View {
        TextEditor(text: $text)
            .font(TD.Font.body())
            .foregroundStyle(TD.primary)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(10)
            .background(
                TD.inputBackground,
                in: RoundedRectangle(cornerRadius: TD.Radius.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TD.Radius.input)
                    .strokeBorder(TD.inputBorder, lineWidth: 2)
            )
    }
}
