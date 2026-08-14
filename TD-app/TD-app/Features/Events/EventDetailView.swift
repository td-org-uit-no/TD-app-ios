import SwiftUI

struct EventDetailView: View {
    let event: Event

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var isJoined: Bool?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingJoinSheet = false
    @State private var showingLeaveConfirm = false
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    /// The edited event, once an admin has saved changes. The view is handed an
    /// immutable `Event` by the navigation link, so a re-read after saving is
    /// what keeps the screen in step with the server.
    @State private var editedEvent: Event?

    /// The freshest version of this event we know about.
    private var current: Event { editedEvent ?? event }

    private var isAdmin: Bool { session.member?.isAdmin == true }

    private var isPast: Bool { current.date < .now }

    var body: some View {
        ZStack(alignment: .top) {
            TDScreenBackground()

            VStack(spacing: 0) {
                TDPageHeader(current.title, back: { dismiss() }) {
                    if isAdmin { adminMenu }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        banner
                        header
                        facts

                        if !current.description.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Om arrangementet")
                                    .font(TD.Font.heading())
                                    .foregroundStyle(TD.primary)
                                // The site renders descriptions with `white-space: pre-wrap`.
                                Text(current.description)
                                    .font(TD.Font.body())
                                    .foregroundStyle(TD.cardTitle)
                                    .textSelection(.enabled)
                            }
                        }

                        if let extra = current.extraInformation, !extra.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Praktisk informasjon")
                                    .font(TD.Font.heading())
                                    .foregroundStyle(TD.primary)
                                Text(extra)
                                    .font(TD.Font.body())
                                    .foregroundStyle(TD.cardTitle)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(TD.Font.small())
                                .foregroundStyle(TD.error)
                        }

                        // The join bar scrolls with the content rather than
                        // being pinned as a bottom safe-area inset.
                        //
                        // As an inset it existed only for upcoming events —
                        // `joinBar` is empty once an event is past — so the two
                        // kinds of event got scroll views of different heights
                        // with different bottom insets, and scrolling an
                        // upcoming event behaved differently from a past one.
                        // In the content, both scroll identically.
                        joinBar
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        // The bar is hidden in favour of `TDPageHeader`, which carries the
        // title, the back action and the admin menu itself.
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task { await loadJoinState() }
        .sheet(isPresented: $showingJoinSheet) {
            JoinEventSheet(event: current) { payload in
                await join(with: payload)
            }
        }
        .sheet(isPresented: $showingLeaveConfirm) {
            LeaveEventSheet(event: current, isLate: isLateCancellation) {
                await leaveReturningError()
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EventFormView(mode: .edit(current)) { await reloadEvent() }
        }
        .confirmationDialog(
            "Slette «\(current.title)»?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Slett", role: .destructive) { Task { await deleteEvent() } }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Dette kan ikke angres.")
        }
    }

    private var adminMenu: some View {
        Menu {
            Button {
                showingEditSheet = true
            } label: {
                Label("Rediger", systemImage: "pencil")
            }

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Slett", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(TD.primary)
        }
        .accessibilityLabel("Administrer arrangement")
    }

    /// Hero image. Events without an uploaded picture 404 here, in which case
    /// we show the TD mark rather than a gap.
    ///
    /// Event posters vary enormously in shape — live data ranges from a
    /// 2000x497 wide banner (4.02:1) to square 1181x1181 posters. They're
    /// artwork with text running to the edges, so cropping them to a fixed
    /// height cuts words off. We scale to fit and let the height follow the
    /// image, capping it so a tall poster can't push the content off-screen.
    private var banner: some View {
        CachedAsyncImage(url: APIClient.shared.eventImageURL(for: event)) { image in
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 260)
        } placeholder: {
            // Shown while loading and for events with no picture; the list has
            // usually cached the poster already, so this rarely flashes.
            ZStack {
                TD.surface
                Image(TD.Asset.logo)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 64)
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
        }
    }

    /// The when and where. The title itself lives in `TDPageHeader` above, so
    /// repeating it here would print the same words twice.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailLine(
                icon: "calendar",
                text: current.date.formatted(
                    .dateTime.weekday(.wide).day().month(.wide).hour().minute()
                )
            )
            DetailLine(icon: "mappin.and.ellipse", text: current.address)
            if !current.location.isEmpty {
                DetailLine(icon: "door.left.hand.open", text: current.location)
            }
        }
    }

    private var facts: some View {
        HStack(spacing: 10) {
            FactChip(
                title: "Pris",
                value: current.isFree ? "Gratis" : "\(current.price) kr",
                icon: "creditcard"
            )
            if let max = current.maxParticipants {
                FactChip(title: "Plasser", value: "\(max)", icon: "person.3")
            }
            if current.food {
                FactChip(title: "Mat", value: "Ja", icon: "fork.knife")
            }
            if current.transportation {
                FactChip(title: "Transport", value: "Ja", icon: "bus")
            }
        }
    }

    @ViewBuilder
    private var joinBar: some View {
        if !isPast {
            VStack(spacing: 8) {
                if current.bindingRegistration, isJoined != true {
                    Text("Bindende påmelding")
                        .font(TD.Font.small())
                        .foregroundStyle(TD.warning)
                }

                if session.isSignedIn {
                    Button {
                        if isJoined == true {
                            showingLeaveConfirm = true
                        } else if current.food || current.transportation {
                            // The site only asks for preferences when the event
                            // actually offers food or transport.
                            showingJoinSheet = true
                        } else {
                            Task { await joinDirectly() }
                        }
                    } label: {
                        if isWorking {
                            ProgressView().tint(TD.secondary)
                        } else {
                            // Labels match the website's EventButton.
                            Text(isJoined == true ? "Meld av!" : "Bli med!")
                        }
                    }
                    .buttonStyle(TDButtonStyle(variant: .secondary))
                    .disabled(isWorking || isJoined == nil)
                } else {
                    Text("Logg inn for å melde deg på")
                        .font(TD.Font.subtitle())
                        .foregroundStyle(TD.inactiveLabel)
                }
            }
            // No padding or backing plate of its own: this sits in the scroll
            // content, which already carries the page's horizontal padding, so
            // the bar reads as the last block on the page rather than as a
            // separate pinned surface.
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }

    private func loadJoinState() async {
        guard session.isSignedIn, !isPast else { return }
        isJoined = try? await APIClient.shared.isJoined(eventID: event.eid)
    }

    /// Re-reads the event after an admin edit. The update endpoint returns no
    /// body, so this is the only way to show what was actually stored.
    ///
    /// A poster is served from a fixed per-event URL, so the cache is cleared
    /// too — otherwise a replaced image would keep showing the old one.
    private func reloadEvent() async {
        ImageStore.shared.invalidateAll()
        if let fresh = try? await APIClient.shared.event(id: event.eid) {
            editedEvent = fresh
        }
    }

    private func deleteEvent() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await APIClient.shared.deleteEvent(id: event.eid)
            // The event is gone, so this screen has nothing left to show.
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
                ?? "Kunne ikke slette arrangementet."
        }
    }

    /// Signs up with the options chosen in the sheet. Returns an error message
    /// for the sheet to display, or nil on success.
    ///
    /// This writes to the same database the website reads, so the member shows
    /// up on td-uit.no's attendee list immediately — there is no separate sync.
    private func join(with payload: JoinEventPayload) async -> String? {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await APIClient.shared.join(eventID: event.eid, options: payload)
            isJoined = true
            return nil
        } catch {
            // The API returns useful detail here — "Event registration is not
            // open", "User already joined", "Event is full" — so surface it.
            return (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Joins without prompting, for events that offer neither food nor
    /// transport — matching the website, which skips its preferences modal in
    /// that case.
    private func joinDirectly() async {
        if let error = await join(with: JoinEventPayload()) {
            errorMessage = error
        }
    }

    /// The site treats cancelling within 24 hours of the start as late, and
    /// warns that it may incur a penalty (`valid_cancellation` in EventButton).
    private var isLateCancellation: Bool {
        current.date.timeIntervalSinceNow < 24 * 60 * 60
    }

    /// Leaves the event, returning an error message for the sheet to show
    /// rather than surfacing it behind the sheet on the detail page.
    private func leaveReturningError() async -> String? {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await APIClient.shared.leave(eventID: event.eid)
            isJoined = false
            return nil
        } catch {
            return (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct DetailLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(TD.red)
                .frame(width: 18)
            Text(text)
                .font(TD.Font.body())
                .foregroundStyle(TD.cardTitle)
        }
    }
}

struct FactChip: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(TD.red)
            Text(value)
                .font(TD.Font.body().weight(.semibold))
                .foregroundStyle(TD.primary)
            Text(title)
                .font(TD.Font.small())
                .foregroundStyle(TD.inactiveLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(TD.surface, in: RoundedRectangle(cornerRadius: TD.Radius.card))
    }
}
