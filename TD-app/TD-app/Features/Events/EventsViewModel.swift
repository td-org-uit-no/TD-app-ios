import Foundation

@MainActor
@Observable
final class EventsViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case upcoming = "Kommende"
        case past = "Tidligere"
        var id: Self { self }

        /// Empty-state wording. Kept here so the list view itself is free of
        /// per-tab conditionals — the two tabs render through one identical
        /// code path and differ only in their data and these strings.
        var emptyTitle: String {
            switch self {
            case .upcoming: "Ingen kommende arrangementer"
            case .past: "Ingen arrangementer"
            }
        }

        var emptyMessage: String {
            switch self {
            case .upcoming: "Det er ingenting planlagt akkurat nå. Sjekk igjen senere!"
            case .past: "Fant ingen tidligere arrangementer."
            }
        }
    }

    var tab: Tab = .upcoming

    private(set) var upcoming: [Event] = []
    private(set) var past: [Event] = []
    /// A full refresh (shows the centred spinner when the list is empty).
    private(set) var isLoading = false
    /// An append of the next page (shows the footer spinner only).
    private(set) var isLoadingPage = false
    private(set) var errorMessage: String?

    /// Bumped by every `load()`. Results from an earlier generation are stale
    /// — the tab was switched or the list re-loaded while they were in flight —
    /// and are dropped rather than written into the current list.
    private var generation = 0
    private var pastTotal: Int?
    /// How many rows the server has returned for the "past" tab so far.
    ///
    /// This is deliberately *not* `past.count`. The endpoint paginates with a
    /// server-side `$skip` over raw documents, while `past` holds the list after
    /// `deduplicatedByID()` has removed repeats — and the live database does
    /// serve the same event more than once. Using the deduplicated count as
    /// `skip` asks the server to re-send rows it has already sent, which the
    /// duplicate filter then discards, so each page appears to deliver a
    /// different number of events. Counting rows keeps `skip` aligned with what
    /// the server is actually counting.
    private var pastRowsFetched = 0
    /// The `eid`s already in `past`, kept in step with it so the pagination
    /// filter is a set lookup rather than a rebuild of the whole list per page.
    private var pastIDs: Set<UUID> = []
    /// Fixed by the server — `/past-events` ignores any `limit` we send.
    private let pageSize = APIClient.pastEventsPageSize
    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    var events: [Event] {
        switch tab {
        case .upcoming: upcoming
        case .past: past
        }
    }

    /// `pastTotal` counts documents on the server, so it is compared against
    /// the rows fetched rather than against `past.count`, which deduplication
    /// can leave permanently short of the total.
    var canLoadMorePast: Bool {
        guard let pastTotal else { return true }
        return pastRowsFetched < pastTotal
    }

    /// Loads the current tab unless it already holds data.
    ///
    /// This is what the view's `.task` calls. That task is keyed on the tab and
    /// lives inside a `TabView`, so it re-fires every time the user returns to
    /// the Events tab — which previously meant a full refetch of the list on
    /// each visit. Bouncing between tabs was re-downloading everything it had
    /// just downloaded, and waking the radio to do it.
    ///
    /// Pull-to-refresh still calls `load()` directly, so asking for fresh data
    /// explicitly is unaffected.
    func loadIfNeeded() async {
        guard events.isEmpty else { return }
        await load()
    }

    func load() async {
        // Claim this load. Switching tabs cancels the previous `.task`, but a
        // request already in flight still resumes and would otherwise write its
        // results into the shared arrays — so a page fetched for an earlier
        // visit could append to a list that has since been reset. Every write
        // below is gated on still owning the current generation.
        generation += 1
        let generation = generation

        // Any page still in flight belongs to the previous generation and will
        // discard its own results, so the flag it set is cleared here rather
        // than waiting for that task to unwind.
        isLoadingPage = false
        isLoading = true
        errorMessage = nil
        // Only the newest load clears the spinner. A superseded load finishing
        // late must not turn it off while its replacement is still running —
        // and it can't leave the flag stuck either, because the load that
        // superseded it sets it again on the way in and owns clearing it.
        defer { if generation == self.generation { isLoading = false } }

        do {
            switch tab {
            case .upcoming: try await loadUpcoming(generation: generation)
            case .past: try await loadFirstPastPage(generation: generation)
            }
        } catch {
            guard generation == self.generation else { return }
            errorMessage = (error as? APIError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// The upcoming list, loaded the same way the past list is.
    ///
    /// The endpoint serves the whole list rather than pages, so there is no
    /// cursor to advance — but the list is otherwise fetched, deduplicated and
    /// installed exactly as `loadFirstPastPage` does it, so the two tabs differ
    /// only in which request they make.
    private func loadUpcoming(generation: Int) async throws {
        let events = try await api.upcomingEvents()
        guard generation == self.generation else { return }
        replaceUpcoming(with: events)
    }

    /// Installs the upcoming list, mirroring `replacePast`.
    private func replaceUpcoming(with events: [Event]) {
        upcoming = events
    }

    /// The first page of past events, plus the total the pagination compares
    /// against. The four `past*` properties describe one page cursor, so they
    /// are always written together — see `replacePast`.
    private func loadFirstPastPage(generation: Int) async throws {
        async let page = api.pastEventsPage(skip: 0)
        async let total = api.pastEventsCount()
        let (events, rowCount) = try await page
        let count = try await total
        guard generation == self.generation else { return }
        replacePast(with: events, rowsFetched: rowCount, total: count)
    }

    /// Resets the "past" tab's list and its page cursor as one unit.
    ///
    /// `past`, `pastIDs` and `pastRowsFetched` have to agree: `pastIDs` is the
    /// duplicate filter for `past`, and `pastRowsFetched` is the server-side
    /// `skip` the next page is asked for. Updating one without the others
    /// desynchronises pagination, so they are only ever written here and in
    /// `loadMorePast`.
    private func replacePast(with events: [Event], rowsFetched: Int, total: Int?) {
        past = events
        pastIDs = Set(events.map(\.eid))
        pastRowsFetched = rowsFetched
        pastTotal = total
    }

    /// Changes with each page appended, so the list's single prefetch task
    /// re-fires for the next page while the trigger stays on screen. Without
    /// this the task would run once and pagination would stop after one page.
    var paginationToken: Int { pastRowsFetched }

    /// Pagination for the "past events" tab, which has ~150 entries.
    ///
    /// Driven by a lone trigger at the end of the list rather than by a check on
    /// each row: the trigger is inside a `LazyVStack`, so it is built only when
    /// the user scrolls within reach of the bottom — which is the same moment
    /// the old per-row distance check fired, at one task instead of one per row.
    func loadMorePast() async {
        guard tab == .past, !isLoadingPage, canLoadMorePast else { return }

        // A page fetched for a previous visit to this tab must not append to the
        // list rebuilt since, so this run is tied to the load that started it.
        let generation = generation

        isLoadingPage = true
        // Only the current generation clears this. A stale page finishing late
        // must not switch off the footer spinner of the load that replaced it;
        // `load()` already reset the flag when it took over, so this cannot
        // leave it stuck on.
        defer { if generation == self.generation { isLoadingPage = false } }

        do {
            // Keep pulling pages until one yields an event not already shown.
            // A page can consist entirely of duplicates, which adds no row for
            // the list to scroll onto — without this loop, nothing would
            // re-trigger the prefetch and pagination would stall short of the
            // end.
            while canLoadMorePast {
                let (next, rowCount) = try await api.pastEventsPage(skip: pastRowsFetched)
                guard generation == self.generation else { return }
                pastRowsFetched += rowCount

                if rowCount == 0 {
                    // The server has nothing further to give, whatever the
                    // count endpoint claimed — stop asking, or we'd spin
                    // forever.
                    pastTotal = pastRowsFetched
                    break
                }

                // `pastIDs` is maintained alongside `past` rather than rebuilt
                // from it here: this loop can run several times per page, and
                // each rebuild walked the entire accumulated list.
                let fresh = next.filter { !pastIDs.contains($0.eid) }
                pastIDs.formUnion(fresh.lazy.map(\.eid))
                past += fresh

                if !fresh.isEmpty { break }
            }
        } catch {
            guard generation == self.generation else { return }
            errorMessage = (error as? APIError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
