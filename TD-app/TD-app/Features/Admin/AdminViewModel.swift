import Foundation

/// Backs the admin page. Each section loads independently so one failing
/// endpoint — stats in particular, which is empty on a fresh database — doesn't
/// blank out the others.
@MainActor
@Observable
final class AdminViewModel {
    enum Section: String, CaseIterable, Identifiable {
        case stats = "Statistikk"
        case members = "Medlemmer"
        case events = "Arrangementer"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .stats: "chart.line.uptrend.xyaxis"
            case .members: "person.2"
            case .events: "calendar"
            }
        }
    }

    var section: Section = .stats

    // Stats
    private(set) var visits: [VisitPoint] = []
    private(set) var pages: [PageStat] = []
    private(set) var isLoadingStats = false
    private(set) var statsError: String?

    // Members
    private(set) var members: [Member] = []
    private(set) var isLoadingMembers = false
    private(set) var membersError: String?

    // Events
    private(set) var events: [Event] = []
    private(set) var isLoadingEvents = false
    private(set) var eventsError: String?

    /// Feedback for a completed write, shown briefly at the top of the page.
    var statusMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Visitors over the last 30 days, oldest first, dropping any bucket whose
    /// date the app can't parse.
    ///
    /// Stored rather than computed: the chart body reads it once to test
    /// `isEmpty` and again to plot, so every render parsed and sorted the whole
    /// series at least twice. It only changes when `visits` does, so it is
    /// derived there instead.
    private(set) var visitSeries: [(date: Date, count: Int)] = []

    /// Likewise derived once per load rather than per render.
    private(set) var totalVisits = 0
    private(set) var peakVisits = 0

    /// Recomputes everything that depends on `visits`.
    private func refreshVisitDerivations() {
        visitSeries = visits
            .compactMap { point in
                point.parsedDate.map { (date: $0, count: point.count) }
            }
            .sorted { $0.date < $1.date }
        totalVisits = visits.reduce(0) { $0 + $1.count }
        peakVisits = visits.map(\.count).max() ?? 0
    }

    /// Members whose account is still awaiting e-mail confirmation — the group
    /// an admin most often needs to act on.
    var unconfirmedCount: Int {
        members.filter { $0.role == .unconfirmed }.count
    }

    /// Loads the visible section unless it already holds data.
    ///
    /// The view keys its `.task` on `section`, so flipping between the three
    /// segments refetched each one every time it came back into view. The
    /// sections all have their own pull-to-refresh for asking again on purpose.
    func loadCurrentSection() async {
        switch section {
        case .stats where !visits.isEmpty || !pages.isEmpty: return
        case .members where !members.isEmpty: return
        case .events where !events.isEmpty: return
        case .stats: await loadStats()
        case .members: await loadMembers()
        case .events: await loadEvents()
        }
    }

    func loadStats() async {
        isLoadingStats = true
        statsError = nil
        defer { isLoadingStats = false }

        // A month back matches the window the page-visit endpoint uses, so the
        // two charts describe the same period.
        let start = Calendar.current.date(byAdding: .day, value: -30, to: .now)

        do {
            async let visitsTask = api.uniqueVisits(from: start)
            async let pagesTask = api.mostVisitedPages()
            (visits, pages) = try await (visitsTask, pagesTask)
            refreshVisitDerivations()
        } catch {
            statsError = Self.message(for: error)
        }
    }

    func loadMembers() async {
        isLoadingMembers = true
        membersError = nil
        defer { isLoadingMembers = false }

        do {
            members = try await api.allMembers()
                .sorted { $0.realName.localizedCaseInsensitiveCompare($1.realName) == .orderedAscending }
        } catch {
            membersError = Self.message(for: error)
        }
    }

    func loadEvents() async {
        isLoadingEvents = true
        eventsError = nil
        defer { isLoadingEvents = false }

        do {
            // The admin table wants everything, not just what's upcoming, so
            // both lists are merged and shown newest first. The past list is
            // paginated 10 at a time, so it has to be walked to the end —
            // `pastEvents()` alone would stop at the first page.
            async let upcoming = api.upcomingEvents()
            async let past = api.allPastEvents()
            events = try await (upcoming + past)
                .deduplicatedByID()
                .sorted { $0.date > $1.date }
        } catch {
            eventsError = Self.message(for: error)
        }
    }

    // MARK: - Mutations
    //
    // Each reloads its section afterwards rather than patching the local array:
    // the write endpoints return no body, so a re-read is the only way to know
    // what the server actually stored.

    func setRole(_ role: Role, for member: Member) async {
        await perform("Rolle oppdatert") {
            try await self.api.adminUpdateMember(
                id: member.id, update: AdminMemberUpdate(role: role)
            )
            await self.loadMembers()
        }
    }

    func setStatus(_ status: MemberStatus, for member: Member) async {
        await perform("Status oppdatert") {
            try await self.api.adminUpdateMember(
                id: member.id, update: AdminMemberUpdate(status: status)
            )
            await self.loadMembers()
        }
    }

    func setPenalty(_ penalty: Int, for member: Member) async {
        await perform(penalty == 0 ? "Prikker fjernet" : "Prikker oppdatert") {
            try await self.api.setPenalty(memberID: member.id, penalty: penalty)
            await self.loadMembers()
        }
    }

    func deleteMember(_ member: Member) async {
        await perform("Medlem slettet") {
            try await self.api.deleteMember(id: member.id)
            await self.loadMembers()
        }
    }

    func deleteEvent(_ event: Event) async {
        await perform("Arrangement slettet") {
            try await self.api.deleteEvent(id: event.eid)
            await self.loadEvents()
        }
    }

    /// Runs a write, reporting either a success note or the failure in-place.
    private func perform(
        _ successMessage: String,
        _ work: @escaping () async throws -> Void
    ) async {
        statusMessage = nil
        do {
            try await work()
            statusMessage = successMessage
        } catch {
            statusMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        guard let apiError = error as? APIError else {
            return error.localizedDescription
        }
        if case .unauthorized = apiError {
            return "Du har ikke administratortilgang."
        }
        return apiError.errorDescription ?? "Noe gikk galt."
    }
}
