import SwiftUI

@MainActor
@Observable
final class JobsViewModel {
    private(set) var jobs: [Job] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Loads the listings unless they are already in hand.
    ///
    /// The view's `.task` sits inside a `TabView`, so it re-fires on every
    /// return to the Stillinger tab. Without this guard each visit refetched a
    /// list that was already on screen, waking the radio for nothing.
    /// Pull-to-refresh calls `load()` directly and is unaffected.
    func loadIfNeeded() async {
        guard jobs.isEmpty else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            jobs = try await api.jobs()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

struct JobsView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = JobsViewModel()
    @State private var showingCreateJob = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                TDScreenBackground()

                VStack(spacing: 0) {
                    header
                    content
                }
            }
            // The bar stays hidden: `TDPageHeader` names the page as ordinary
            // content, so there is no second surface colour across the top.
            // `JobDetailView` draws its own header when pushed.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Job.self) { JobDetailView(job: $0) }
        }
        .tint(TD.red)
        // See `loadIfNeeded`: this re-fires on every return to the tab, and the
        // pull-to-refresh below is what forces an actual reload.
        .task { await model.loadIfNeeded() }
        .sheet(isPresented: $showingCreateJob) {
            JobFormView(mode: .create) { await model.load() }
        }
    }

    /// Carries the create button for admins, mirroring the events list.
    private var header: some View {
        TDPageHeader("Stillinger", trailing: {
            if session.member?.isAdmin == true {
                Button {
                    showingCreateJob = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TD.primary)
                        .frame(width: 34, height: 34)
                        .background(TD.red, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ny stilling")
            }
        })
    }

    @ViewBuilder
    private var content: some View {
        if model.jobs.isEmpty, model.isLoading {
            Spacer()
            ProgressView().tint(TD.primary)
            Spacer()
        } else if let error = model.errorMessage, model.jobs.isEmpty {
            Spacer()
            ErrorStateView(message: error) { await model.load() }
            Spacer()
        } else if model.jobs.isEmpty {
            Spacer()
            EmptyStateView(
                title: "Ingen stillinger",
                message: "Fant ingen utlysninger akkurat nå.",
                icon: "briefcase"
            )
            Spacer()
        } else {
            // Vertical only, matching the events list.
            ScrollView(.vertical) {
                LazyVStack(spacing: 10) {
                    ForEach(model.jobs) { job in
                        NavigationLink(value: job) { JobCard(job: job) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            // Matches the events list, which hides them for the same reason:
            // the cards run nearly the full width, so the bar overlaps them.
            .scrollIndicators(.hidden)
            .refreshable {
                // Company logos live at a fixed URL per job, so a replaced
                // logo is invisible to the caches until they are told to
                // look again.
                ImageStore.shared.invalidateAll()
                await model.load()
            }
        }
    }
}

/// Matches the site's `jobCard.module.scss`, with capitalised orange tag pills.
///
/// Built on `TDCard`, the same surface `EventRow` uses, so the two lists share
/// one radius, fill and shadow rather than each maintaining its own copy.
struct JobCard: View {
    let job: Job

    private var isExpired: Bool {
        guard let due = job.dueDate else { return false }
        return due < .now
    }

    var body: some View {
        TDCard(height: TD.Card.jobHeight) {
            VStack(alignment: .leading, spacing: TD.Card.spacing) {
                // Artwork, then the title block, then a trailing tag — the same
                // three-part row `EventRow` opens with, mirrored so the logo
                // leads and the type pill trails.
                HStack(alignment: .top, spacing: 10) {
                    CompanyLogo(job: job, size: TD.Card.thumbnail)

                    VStack(alignment: .leading, spacing: TD.Card.titleGap) {
                        Text(job.title)
                            .font(TD.Font.cardTitle())
                            .foregroundStyle(TD.primary)
                            // Wrap onto a second line rather than shrinking, so
                            // job and event titles render at one consistent size.
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        // `cardSubtitle`, matching the address line that sits in
                        // the same position on an event card.
                        Text("@\(job.company)")
                            .font(TD.Font.subtitle())
                            .foregroundStyle(TD.cardSubtitle)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TDTag(text: job.type, color: TD.activeLabel)
                }

                Text(job.descriptionPreview)
                    .font(TD.Font.subtitle())
                    .foregroundStyle(TD.cardSubtitle)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                if !job.displayTags.isEmpty {
                    HStack(spacing: TD.Card.tagGap) {
                        ForEach(job.displayTags.prefix(3), id: \.self) { tag in
                            TDTag(text: tag)
                        }
                    }
                }

                // Holds the footer to the card's baseline. With a fixed height
                // there is slack inside the card, and without this the content
                // would sit centred rather than reading top-down.
                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Label(job.location, systemImage: "mappin.and.ellipse")
                    if let due = job.dueDate {
                        Label {
                            Text("Frist \(due, format: .dateTime.day().month())")
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .foregroundStyle(isExpired ? TD.error : TD.inactiveLabel)
                    }
                }
                .font(TD.Font.small())
                .foregroundStyle(TD.inactiveLabel)
            }
            .padding(TD.Card.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The round company logo the site shows on a listing (`.card_img`).
///
/// Served by `GET /api/jobs/{id}/image`, which production has for every
/// listing. Seeded local jobs have no picture and 404, so they show a neutral
/// mark — a card should never render a blank hole where the logo goes.
struct CompanyLogo: View {
    let job: Job
    let size: CGFloat

    var body: some View {
        CachedAsyncImage(url: APIClient.shared.jobImageURL(for: job)) { image in
            // Fit, not fill: these are wordmarks with wide aspect ratios, and
            // filling the frame would crop the company name off.
            image
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } placeholder: {
            placeholder
        }
        .frame(width: size, height: size)
    }

    /// A neutral mark, for listings with no uploaded logo.
    private var placeholder: some View {
        // Mid-grey, not `TD.background`: the mark used to sit on a white
        // circle, and against the dark card that near-black would be invisible.
        Image(systemName: "building.2.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(TD.offPrimary)
            .padding(size * 0.22)
    }
}

struct JobDetailView: View {
    let job: Job

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    /// The edited listing, once an admin has saved changes. The view is handed
    /// an immutable `Job` by the navigation link, so a re-read after saving is
    /// what keeps the screen in step with the server.
    @State private var editedJob: Job?

    /// The freshest version of this listing we know about.
    private var current: Job { editedJob ?? job }

    private var isAdmin: Bool { session.member?.isAdmin == true }

    private var cleanTags: [String] { current.displayTags }

    var body: some View {
        ZStack(alignment: .top) {
            TDScreenBackground()

            VStack(spacing: 0) {
                TDPageHeader(current.company, back: { dismiss() }) {
                    if isAdmin { adminMenu }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            // The company's name is in the page header above,
                            // so only its logo is repeated here, next to the
                            // job title it belongs to.
                            HStack(alignment: .top, spacing: 10) {
                                CompanyLogo(job: current, size: 44)
                                Text(current.title)
                                    .font(TD.Font.title())
                                    .foregroundStyle(TD.primary)
                            }
                            DetailLine(icon: "mappin.and.ellipse", text: current.location)
                            if let due = current.dueDate {
                                DetailLine(
                                    icon: "calendar.badge.exclamationmark",
                                    text: "Søknadsfrist \(due.formatted(.dateTime.day().month(.wide).year()))"
                                )
                            }
                        }

                        if !cleanTags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(cleanTags, id: \.self) { tag in
                                        TDTag(text: tag)
                                    }
                                }
                            }
                        }

                        Divider().overlay(TD.inputBorder)

                        // The API returns Markdown, which SwiftUI renders inline.
                        Text(LocalizedStringKey(current.description))
                            .font(TD.Font.body())
                            .foregroundStyle(TD.cardTitle)
                            .textSelection(.enabled)
                            .tint(TD.info)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(TD.Font.small())
                                .foregroundStyle(TD.error)
                        }

                        if let url = URL(string: current.link) {
                            Link(destination: url) {
                                Label("Se utlysning", systemImage: "arrow.up.right.square")
                                    .font(TD.Font.body().weight(.semibold))
                                    .foregroundStyle(TD.primary)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        TD.red,
                                        in: RoundedRectangle(cornerRadius: TD.Radius.input)
                                    )
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        // The bar is hidden in favour of `TDPageHeader`, which carries the
        // company name, the back action and the admin menu itself.
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showingEditSheet) {
            JobFormView(mode: .edit(current)) { await reloadJob() }
        }
        .confirmationDialog(
            "Slette «\(current.title)»?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Slett", role: .destructive) { Task { await deleteJob() } }
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
        .accessibilityLabel("Administrer stilling")
        .disabled(isDeleting)
    }

    /// Re-reads the listing after an edit, so the screen shows what was saved
    /// rather than the copy the list handed over.
    private func reloadJob() async {
        do {
            editedJob = try await APIClient.shared.job(id: job.id)
        } catch {
            // The write itself succeeded — only the refresh failed, so the
            // stale copy stays on screen rather than an error replacing it.
            errorMessage = "Endringene ble lagret, men siden er ikke oppdatert."
        }
    }

    private func deleteJob() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }

        do {
            try await APIClient.shared.deleteJob(id: job.id)
            // The listing is gone, so this screen has nothing left to show.
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
                ?? "Kunne ikke slette stillingen."
        }
    }
}
