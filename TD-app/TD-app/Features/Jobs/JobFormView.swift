import PhotosUI
import SwiftUI

/// Creates or edits a job listing. Admin only.
///
/// The field set mirrors the website's job form (`JobForm.tsx`): company, type,
/// tags, title, location, link, an application deadline and start date, a short
/// preview description, the full description, and a PNG company logo.
///
/// One form serves both modes, but they hit different endpoints with different
/// rules:
///
/// - **Create** posts a `JobInput`, where every field but the two dates is
///   required, then uploads the logo in a second request against the returned
///   id.
/// - **Edit** sends a `JobUpdate` containing *only* what changed. The backend
///   re-validates the merged job and rejects an update that would clear a
///   required field, so unchanged fields are omitted rather than re-sent.
///
/// Unlike events, no date here has to be in the future — a listing's deadline
/// may legitimately have passed.
struct JobFormView: View {
    enum Mode {
        case create
        case edit(Job)
    }

    let mode: Mode
    /// Called after a successful write so the caller can reload its list.
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var company: String
    @State private var title: String
    @State private var type: String
    @State private var tagsText: String
    @State private var location: String
    /// Held without the `https://` prefix, which the site shows as a fixed
    /// affix and prepends on submit.
    @State private var link: String
    @State private var descriptionPreview: String
    @State private var descriptionText: String

    /// Both dates are optional on the API, so each is a toggle plus a picker
    /// rather than a bare date.
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var hasStartDate: Bool
    @State private var startDate: Date

    @State private var logoItem: PhotosPickerItem?
    @State private var logoData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Field length caps, matching the website's validators one for one. The
    /// API itself imposes none, so these exist to keep the two clients from
    /// disagreeing about what a valid listing looks like.
    private enum Limit {
        static let company = 50
        static let title = 50
        static let type = 35
        static let location = 100
        static let link = 500
        static let descriptionPreview = 750
        static let description = 7500
    }

    init(mode: Mode, onSaved: @escaping () async -> Void) {
        self.mode = mode
        self.onSaved = onSaved

        let job: Job? = if case let .edit(existing) = mode { existing } else { nil }

        _company = State(initialValue: job?.company ?? "")
        _title = State(initialValue: job?.title ?? "")
        _type = State(initialValue: job?.type ?? "")
        // The site joins and splits tags on spaces, so a tag can't contain one.
        _tagsText = State(initialValue: job?.tags.joined(separator: " ") ?? "")
        _location = State(initialValue: job?.location ?? "")
        _link = State(initialValue: Self.stripScheme(job?.link ?? ""))
        _descriptionPreview = State(initialValue: job?.descriptionPreview ?? "")
        _descriptionText = State(initialValue: job?.description ?? "")

        let due = job?.dueDate
        _hasDueDate = State(initialValue: due != nil)
        _dueDate = State(initialValue: due ?? Self.defaultDueDate)

        let start = job?.startDate
        _hasStartDate = State(initialValue: start != nil)
        _startDate = State(initialValue: start ?? Self.defaultDueDate)
    }

    /// A new listing defaults its deadline a month out, a plausible slot that
    /// still has to be confirmed by ticking the toggle.
    private static var defaultDueDate: Date {
        Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    }

    /// Drops a leading scheme so the field shows what the site's does. Stored
    /// links are written with `https://`, but the seed data isn't consistent
    /// about it, so `http://` is handled too.
    private static func stripScheme(_ link: String) -> String {
        for scheme in ["https://", "http://"] where link.hasPrefix(scheme) {
            return String(link.dropFirst(scheme.count))
        }
        return link
    }

    private var existingJob: Job? {
        if case let .edit(job) = mode { return job }
        return nil
    }

    private var isEditing: Bool { existingJob != nil }

    // MARK: - Validation

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCompany: String { trimmed(company) }
    private var trimmedTitle: String { trimmed(title) }
    private var trimmedType: String { trimmed(type) }
    private var trimmedLocation: String { trimmed(location) }
    private var trimmedPreview: String { trimmed(descriptionPreview) }
    private var trimmedDescription: String { trimmed(descriptionText) }

    /// Space-separated, as on the website. Empty entries are dropped so a
    /// stray double space doesn't become a blank tag.
    private var tags: [String] {
        tagsText.split(separator: " ").map(String.init)
    }

    /// The link as the API stores it. The site hardcodes `https://`, and the
    /// field never contains a scheme because the picker strips it on load and
    /// `linkError` rejects one on entry.
    private var fullLink: String { "https://\(trimmed(link))" }

    /// Mirrors the site's `JobLinkValidator`, which rejects a pasted scheme
    /// rather than silently sending `https://https://…`.
    private var linkError: String? {
        let value = trimmed(link)
        if value.count >= Limit.link { return "Lenken er for lang." }
        if value.hasPrefix("https://") || value.hasPrefix("http://") {
            return "Ugyldig lenke — fjern «https://»."
        }
        return nil
    }

    private func lengthError(_ value: String, max: Int, label: String) -> String? {
        value.count >= max ? "\(label) er for lang." : nil
    }

    /// Every length complaint currently on screen, in field order.
    private var validationErrors: [String] {
        [
            lengthError(trimmedCompany, max: Limit.company, label: "Bedriftsnavnet"),
            lengthError(trimmedType, max: Limit.type, label: "Typen"),
            lengthError(trimmedTitle, max: Limit.title, label: "Tittelen"),
            lengthError(trimmedLocation, max: Limit.location, label: "Lokasjonen"),
            linkError,
            lengthError(
                trimmedPreview, max: Limit.descriptionPreview,
                label: "Forhåndsvisningen"
            ),
            lengthError(
                trimmedDescription, max: Limit.description, label: "Beskrivelsen"
            ),
        ].compactMap { $0 }
    }

    /// The API requires all of these, so an empty one is a 422.
    private var hasRequiredFields: Bool {
        !trimmedCompany.isEmpty
            && !trimmedTitle.isEmpty
            && !trimmedType.isEmpty
            && !trimmedLocation.isEmpty
            && !trimmed(link).isEmpty
            && !trimmedPreview.isEmpty
            && !trimmedDescription.isEmpty
    }

    private var canSave: Bool {
        hasRequiredFields
            && validationErrors.isEmpty
            && !isSaving
            && (!isEditing || hasChanges)
    }

    private var hasChanges: Bool { !pendingUpdate.isEmpty || logoData != nil }

    /// The diff against the stored job, used in edit mode.
    private var pendingUpdate: JobUpdate {
        guard let job = existingJob else { return JobUpdate() }

        var update = JobUpdate()
        if trimmedCompany != job.company { update.company = trimmedCompany }
        if trimmedTitle != job.title { update.title = trimmedTitle }
        if trimmedType != job.type { update.type = trimmedType }
        if tags != job.tags { update.tags = tags }
        if trimmedLocation != job.location { update.location = trimmedLocation }
        if fullLink != job.link { update.link = fullLink }
        if trimmedPreview != job.descriptionPreview {
            update.descriptionPreview = trimmedPreview
        }
        if trimmedDescription != job.description {
            update.description = trimmedDescription
        }
        update.dueDate = dateUpdate(
            selected: hasDueDate ? dueDate : nil, stored: job.dueDate
        )
        update.startDate = dateUpdate(
            selected: hasStartDate ? startDate : nil, stored: job.startDate
        )
        return update
    }

    /// Turns a before/after pair into the three-way instruction `JobUpdate`
    /// needs — untouched, replaced, or explicitly cleared.
    private func dateUpdate(
        selected: Date?, stored: Date?
    ) -> JobUpdate.DateFieldUpdate {
        switch (selected, stored) {
        case (nil, nil): .unchanged
        case (nil, _?): .cleared
        case let (value?, stored) where value != stored: .set(value)
        default: .unchanged
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                TDScreenBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        group("Bedrift") {
                            TDTextField(title: "Bedrift", text: $company)
                        }

                        group("Type") {
                            TDTextField(title: "Sommerjobb, fulltid, …", text: $type)
                        }

                        group("Tags (mellomrom mellom hver)") {
                            TDTextField(title: "utvikler backend", text: $tagsText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        group("Tittel") {
                            TDTextField(title: "Tittel", text: $title)
                        }

                        group("Lokasjon") {
                            TDTextField(title: "Tromsø", text: $location)
                        }

                        group("Lenke til utlysningen") {
                            HStack(spacing: 0) {
                                // The scheme is fixed, exactly as the site's
                                // prefixed input presents it.
                                Text("https://")
                                    .font(TD.Font.body())
                                    .foregroundStyle(TD.inactiveLabel)
                                    .padding(.leading, 14)

                                TDTextField(title: "td.uit.no", text: $link)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                            }
                        }

                        dateToggles

                        group("Beskrivelse forhåndsvisning") {
                            TDTextEditor(text: $descriptionPreview, minHeight: 80)
                        }

                        group("Beskrivelse") {
                            TDTextEditor(text: $descriptionText)
                        }

                        logoPicker

                        ForEach(validationErrors, id: \.self) { warning($0) }

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
            .navigationTitle(isEditing ? "Rediger stilling" : "Ny stilling")
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
            .task(id: logoItem) { await loadLogo() }
        }
        .tint(TD.red)
    }

    private var dateToggles: some View {
        VStack(spacing: 0) {
            dateRow(
                "Søknadsfrist", isOn: $hasDueDate, selection: $dueDate
            )
            Divider().overlay(TD.inputBorder)
            dateRow(
                "Startdato", isOn: $hasStartDate, selection: $startDate
            )
        }
        .background(TD.inputBackground, in: RoundedRectangle(cornerRadius: TD.Radius.input))
    }

    /// A toggle that reveals its date picker only once switched on — both dates
    /// are optional, and an untouched listing should send neither.
    private func dateRow(
        _ label: String, isOn: Binding<Bool>, selection: Binding<Date>
    ) -> some View {
        VStack(spacing: 0) {
            tdToggle(label, isOn: isOn)

            if isOn.wrappedValue {
                HStack {
                    DatePicker(
                        "", selection: selection, displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .colorScheme(.dark)
                    .tint(TD.red)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 11)
            }
        }
    }

    /// PNG only, matching the website's file selector — the backend saves
    /// whatever it receives as `.png` regardless of the real format.
    private var logoPicker: some View {
        // Read out of `@State` here, in the isolated body, rather than inside
        // the picker's `@Sendable` label closure below. `Binding` is itself
        // `Sendable`, so the closure captures it without a data-race warning.
        let logo = $logoData

        return VStack(alignment: .leading, spacing: 8) {
            Text("Logo")
                .font(TD.Font.subtitle())
                .foregroundStyle(TD.inactiveLabel)

            PhotosPicker(selection: $logoItem, matching: .images) {
                TDImagePickerLabel(
                    data: logo,
                    placeholderIcon: "building.2",
                    emptyTitle: "Last opp logo til bedriften",
                    selectedTitle: "Logo valgt — trykk for å bytte",
                    contentMode: .fit,
                    onClear: { logoItem = nil }
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
    private func loadLogo() async {
        guard let logoItem else { return }
        guard
            let data = try? await logoItem.loadTransferable(type: Data.self),
            let image = UIImage(data: data),
            let png = image.pngData()
        else {
            errorMessage = "Kunne ikke lese bildet."
            return
        }
        logoData = png
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            if let job = existingJob {
                let update = pendingUpdate
                if !update.isEmpty {
                    try await APIClient.shared.updateJob(id: job.id, update: update)
                }
                if let logoData {
                    try await APIClient.shared.uploadJobImage(
                        id: job.id, pngData: logoData
                    )
                    // The logo URL doesn't change when the image does, so the
                    // cached copy has to be dropped explicitly.
                    ImageStore.shared.invalidateAll()
                }
            } else {
                let id = try await APIClient.shared.createJob(makeInput())
                if let logoData {
                    // The listing exists at this point, so a failed image upload
                    // is reported without discarding the listing itself.
                    do {
                        try await APIClient.shared.uploadJobImage(
                            id: id, pngData: logoData
                        )
                        ImageStore.shared.invalidateAll()
                    } catch {
                        await onSaved()
                        errorMessage = """
                            Stillingen ble opprettet, men logoen ble ikke lastet opp. \
                            Rediger stillingen for å prøve igjen.
                            """
                        return
                    }
                }
            }
            await onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
                ?? "Kunne ikke lagre stillingen."
        }
    }

    private func makeInput() -> JobInput {
        JobInput(
            company: trimmedCompany,
            title: trimmedTitle,
            type: trimmedType,
            tags: tags,
            descriptionPreview: trimmedPreview,
            description: trimmedDescription,
            // Required by the payload model, then overwritten server-side with
            // the insert time — the site sends `new Date()` here for the same
            // reason.
            publishedDate: .now,
            location: trimmedLocation,
            link: fullLink,
            startDate: hasStartDate ? startDate : nil,
            dueDate: hasDueDate ? dueDate : nil
        )
    }
}
