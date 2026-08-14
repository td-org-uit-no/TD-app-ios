import SwiftUI

struct EventsView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = EventsViewModel()
    @State private var showingCreateEvent = false
    @Namespace private var tabAnimation

    var body: some View {
        NavigationStack {
            // One background for the whole screen. The navigation bar is hidden
            // and the header below is drawn as ordinary content, so there is no
            // second surface colour banding across the top.
            ZStack(alignment: .top) {
                TDScreenBackground()

                VStack(spacing: 0) {
                    header
                    content
                }
            }
            // The bar stays hidden: `TDPageHeader` names the page as ordinary
            // content, so there is no second surface colour across the top.
            // `EventDetailView` draws its own header when pushed.
            .toolbar(.hidden, for: .navigationBar)
            // The tab switcher sits at the bottom, within thumb reach and
            // directly above the tab bar, rather than up under the title.
            .safeAreaInset(edge: .bottom) {
                segmentedTabs
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(TD.background)
            }
            .navigationDestination(for: Event.self) { EventDetailView(event: $0) }
        }
        .tint(TD.red)
        // `loadIfNeeded`, not `load`: this task re-fires on every return to the
        // Events tab, and refetching a list already on screen is pure radio
        // wakeup. Pull-to-refresh below still forces a real reload.
        .task(id: model.tab) { await model.loadIfNeeded() }
        .sheet(isPresented: $showingCreateEvent) {
            EventFormView(mode: .create) { await model.load() }
        }
    }

    // MARK: - Header

    private var header: some View {
        TDPageHeader("Arrangementer", trailing: {
            if session.member?.isAdmin == true {
                Button {
                    showingCreateEvent = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TD.primary)
                        .frame(width: 34, height: 34)
                        .background(TD.red, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Nytt arrangement")
            }
        })
    }

    /// Custom segmented control — UIKit's segmented picker can't take the
    /// site's palette, so this draws the TD-red selected pill directly.
    private var segmentedTabs: some View {
        HStack(spacing: 6) {
            ForEach(EventsViewModel.Tab.allCases) { tab in
                let isSelected = model.tab == tab

                Button {
                    withAnimation(.snappy(duration: 0.25)) { model.tab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(TD.Font.body().weight(.semibold))
                        .foregroundStyle(isSelected ? TD.primary : TD.inactiveLabel)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        // The pill is drawn behind the whole cell, and
                        // `contentShape` makes that same area tappable — with
                        // `.plain` only the glyphs themselves take the hit.
                        .background {
                            if isSelected {
                                Capsule(style: .continuous)
                                    .fill(TD.red)
                                    .matchedGeometryEffect(id: "tab", in: tabAnimation)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(5)
        .background {
            Capsule(style: .continuous)
                .fill(TD.inputBackground)
                .overlay(Capsule(style: .continuous).strokeBorder(TD.inputBorder, lineWidth: 1))
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.events.isEmpty, model.isLoading {
            Spacer()
            ProgressView().tint(TD.primary)
            Spacer()
        } else if let error = model.errorMessage, model.events.isEmpty {
            Spacer()
            ErrorStateView(message: error) { await model.load() }
            Spacer()
        } else if model.events.isEmpty {
            Spacer()
            EmptyStateView(
                title: model.tab.emptyTitle,
                message: model.tab.emptyMessage,
                icon: "calendar"
            )
            Spacer()
        } else {
            eventList
        }
    }

    /// The list, identical for both tabs.
    ///
    /// "Kommende" and "Tidligere" differ only in which events `model.events`
    /// holds — every view below is built the same way for both, so the two tabs
    /// cannot lay out or scroll differently from one another. The pagination
    /// trigger is always present rather than conditional on the tab; on
    /// "Kommende" `loadMorePast()` returns at its first guard, so an inert
    /// 1pt spacer is all it costs to keep the two structures the same.
    private var eventList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 10) {
                ForEach(model.events) { event in
                    NavigationLink(value: event) {
                        EventRow(event: event)
                    }
                    .buttonStyle(.plain)
                }

                // One prefetch trigger for the whole list, rather than a `.task`
                // on every row. Being lazy, it is built only once the user
                // scrolls within reach of the bottom — the same moment the old
                // per-row distance check fired, at one task instead of one per
                // row.
                Color.clear
                    .frame(height: 1)
                    .task(id: model.paginationToken) { await model.loadMorePast() }

                if model.isLoadingPage {
                    ProgressView().tint(TD.primary).padding()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            // See JobsView: posters live at a fixed URL per event, so a
            // replaced image needs the caches explicitly cleared.
            ImageStore.shared.invalidateAll()
            await model.load()
        }
    }
}

/// Mirrors the site's horizontal event card (`horizontal.scss`):
/// `#2b2c3d` surface, 0.5rem radius, date on the left, thumbnail on the right.
struct EventRow: View {
    let event: Event

    var body: some View {
        TDCard(height: TD.Card.eventHeight) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: TD.Card.titleGap) {
                    Text(event.date, format: .dateTime.day().month(.abbreviated))
                        .font(TD.Font.subtitle().weight(.semibold))
                    Text(event.date, format: .dateTime.hour().minute())
                        .font(TD.Font.small())
                }
                .foregroundStyle(TD.cardTitle)
                .frame(minWidth: 62, alignment: .leading)

                VStack(alignment: .leading, spacing: TD.Card.titleGap) {
                    Text(event.title)
                        .font(TD.Font.cardTitle())
                        .foregroundStyle(TD.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(event.address)
                        .font(TD.Font.subtitle())
                        .foregroundStyle(TD.cardSubtitle)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: TD.Card.tagGap) {
                        if event.food { TDTag(text: "Mat", icon: "fork.knife") }
                        if event.transportation { TDTag(text: "Transport", icon: "bus") }
                        if !event.isFree {
                            TDTag(text: "\(event.price) kr", icon: "creditcard")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                EventThumbnail(event: event)
            }
            .padding(TD.Card.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Event artwork, rendered flat against the card. Falls back to the TD mark
/// when an event has no picture.
struct EventThumbnail: View {
    let event: Event
    var size: CGFloat = TD.Card.thumbnail

    var body: some View {
        // Always attempt the fetch: the backend serves images for events whose
        // `picturePath` is null, so the 404 is the only reliable signal that an
        // event has no picture. `placeholder` covers that case.
        //
        // Cached rather than `AsyncImage` so a row that scrolls out and back in
        // redraws from memory instead of re-downloading its poster.
        CachedAsyncImage(url: APIClient.shared.eventImageURL(for: event)) { image in
            // Fit rather than fill — these are posters whose text runs to the
            // edges, and their aspect ratios range from 4:1 to square, so
            // filling a square thumbnail would crop the content away.
            image
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } placeholder: {
            placeholder
        }
        .frame(width: size, height: size)
    }

    /// The TD mark alone, for events with no uploaded picture.
    private var placeholder: some View {
        Image(TD.Asset.logo)
            .resizable()
            .scaledToFit()
            .padding(size * 0.22)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var icon: String = "calendar"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(TD.offPrimary)
            Text(title)
                .font(TD.Font.heading())
                .foregroundStyle(TD.primary)
            Text(message)
                .font(TD.Font.body())
                .foregroundStyle(TD.inactiveLabel)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(TD.error)
            Text("Noe gikk galt")
                .font(TD.Font.heading())
                .foregroundStyle(TD.primary)
            Text(message)
                .font(TD.Font.body())
                .foregroundStyle(TD.inactiveLabel)
                .multilineTextAlignment(.center)
            Button("Prøv igjen") { Task { await retry() } }
                .buttonStyle(TDButtonStyle())
                .frame(maxWidth: 200)
        }
        .padding(32)
    }
}
