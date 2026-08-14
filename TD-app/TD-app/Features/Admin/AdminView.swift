import Charts
import SwiftUI

/// The admin area, mirroring the website's `/admin` and `/stats` pages.
///
/// The site splits these across a sidebar (Members / Events / Announcements)
/// and a separate stats route. A phone has no room for a sidebar, so the same
/// sections become a segmented control, and Announcements is left out — it is
/// an unimplemented placeholder on the website too.
///
/// Creating and editing events lives in the Events tab rather than here, so
/// there is one place to manage an event rather than two.
struct AdminView: View {
    @State private var model = AdminViewModel()

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            TDScreenBackground()

            VStack(spacing: 0) {
                TDPageHeader("Adminpanel", back: { dismiss() })

                sectionPicker

                if let status = model.statusMessage {
                    statusBanner(status)
                }

                content
            }
        }
        // The bar is hidden in favour of `TDPageHeader`, which carries the
        // title and the back action.
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task(id: model.section) { await model.loadCurrentSection() }
    }

    private var sectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(AdminViewModel.Section.allCases) { section in
                let isSelected = model.section == section

                Button {
                    withAnimation(.snappy(duration: 0.2)) { model.section = section }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section.icon)
                            .font(.system(size: 11))
                        Text(section.rawValue)
                            .font(TD.Font.small().weight(isSelected ? .semibold : .regular))
                    }
                    .foregroundStyle(isSelected ? TD.primary : TD.inactiveLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 7).fill(TD.red)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(TD.inputBackground, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Write feedback. It doubles as the error channel for failed mutations,
    /// so the colour follows whether the message reads as a success.
    private func statusBanner(_ message: String) -> some View {
        let isError = !AdminView.successMessages.contains(message)

        return HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            Text(message)
                .font(TD.Font.subtitle())
            Spacer(minLength: 0)
            Button {
                model.statusMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(isError ? TD.error : TD.success)
        .padding(12)
        .background(
            (isError ? TD.error : TD.success).opacity(0.15),
            in: RoundedRectangle(cornerRadius: TD.Radius.input)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// The exact strings `AdminViewModel` reports on success.
    private static let successMessages: Set<String> = [
        "Rolle oppdatert", "Status oppdatert", "Prikker oppdatert",
        "Prikker fjernet", "Medlem slettet", "Arrangement slettet",
    ]

    @ViewBuilder
    private var content: some View {
        switch model.section {
        case .stats:
            StatsSection(model: model)
        case .members:
            MembersSection(model: model)
        case .events:
            AdminEventsSection(model: model)
        }
    }
}

// MARK: - Stats

private struct StatsSection: View {
    let model: AdminViewModel

    var body: some View {
        Group {
            if model.isLoadingStats, model.visits.isEmpty, model.pages.isEmpty {
                loading
            } else if let error = model.statsError, model.visits.isEmpty {
                ErrorStateView(message: error) { await model.loadStats() }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        summaryRow
                        visitorsChart
                        pagesChart
                    }
                    .padding(16)
                }
                .refreshable { await model.loadStats() }
            }
        }
    }

    private var loading: some View {
        VStack {
            Spacer()
            ProgressView().tint(TD.primary)
            Spacer()
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            statTile("Besøk", "\(model.totalVisits)", icon: "person.fill.checkmark")
            statTile("Topp dag", "\(model.peakVisits)", icon: "arrow.up.right")
        }
    }

    private func statTile(_ label: String, _ value: String, icon: String) -> some View {
        TDCard {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                    Text(label)
                        .font(TD.Font.small())
                }
                .foregroundStyle(TD.inactiveLabel)

                Text(value)
                    .font(TD.Font.title())
                    .foregroundStyle(TD.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    @ViewBuilder
    private var visitorsChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unike brukere")
                .font(TD.Font.heading())
                .foregroundStyle(TD.primary)
            Text("Siste 30 dager")
                .font(TD.Font.small())
                .foregroundStyle(TD.inactiveLabel)

            TDCard {
                Group {
                    if model.visitSeries.isEmpty {
                        emptyChart("Ingen registrerte besøk ennå.")
                    } else {
                        Chart(model.visitSeries, id: \.date) { point in
                            AreaMark(
                                x: .value("Dato", point.date),
                                y: .value("Besøk", point.count)
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [TD.red.opacity(0.45), TD.red.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Dato", point.date),
                                y: .value("Besøk", point.count)
                            )
                            .foregroundStyle(TD.red)
                            .interpolationMethod(.monotone)
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) {
                                AxisGridLine().foregroundStyle(TD.inputBorder)
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                    .foregroundStyle(TD.inactiveLabel)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) {
                                AxisGridLine().foregroundStyle(TD.inputBorder)
                                AxisValueLabel().foregroundStyle(TD.inactiveLabel)
                            }
                        }
                        .frame(height: 200)
                        .padding(14)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pagesChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mest besøkte sider")
                .font(TD.Font.heading())
                .foregroundStyle(TD.primary)
            Text("Siste 30 dager")
                .font(TD.Font.small())
                .foregroundStyle(TD.inactiveLabel)

            TDCard {
                Group {
                    if model.pages.isEmpty {
                        emptyChart("Ingen sidevisninger registrert.")
                    } else {
                        Chart(model.pages) { page in
                            BarMark(
                                x: .value("Besøk", page.count),
                                y: .value("Side", page.displayName)
                            )
                            .foregroundStyle(TD.activeLabel)
                            .cornerRadius(4)
                            .annotation(position: .trailing) {
                                Text("\(page.count)")
                                    .font(TD.Font.small())
                                    .foregroundStyle(TD.inactiveLabel)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading) {
                                AxisValueLabel().foregroundStyle(TD.cardSubtitle)
                            }
                        }
                        // Enough height per bar that the labels stay legible.
                        .frame(height: CGFloat(model.pages.count) * 42 + 20)
                        .padding(14)
                    }
                }
            }
        }
    }

    private func emptyChart(_ message: String) -> some View {
        Text(message)
            .font(TD.Font.subtitle())
            .foregroundStyle(TD.inactiveLabel)
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(14)
    }
}

// MARK: - Members

private struct MembersSection: View {
    let model: AdminViewModel

    @State private var searchText = ""
    @State private var pendingDeletion: Member?

    private var filtered: [Member] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.members }
        return model.members.filter {
            $0.realName.localizedCaseInsensitiveContains(query)
                || $0.email.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if model.isLoadingMembers, model.members.isEmpty {
                VStack {
                    Spacer()
                    ProgressView().tint(TD.primary)
                    Spacer()
                }
            } else if let error = model.membersError, model.members.isEmpty {
                ErrorStateView(message: error) { await model.loadMembers() }
            } else {
                VStack(spacing: 0) {
                    // The navigation bar is hidden on this screen, so
                    // `.searchable`'s bar drawer has nowhere to live. The field
                    // is drawn as content instead.
                    searchField

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            summary

                            ForEach(filtered) { member in
                                MemberAdminRow(
                                    member: member,
                                    model: model,
                                    onDelete: { pendingDeletion = member }
                                )
                            }

                            if filtered.isEmpty {
                                Text("Ingen medlemmer matcher søket.")
                                    .font(TD.Font.body())
                                    .foregroundStyle(TD.inactiveLabel)
                                    .padding(.top, 24)
                            }
                        }
                        .padding(16)
                    }
                    .refreshable { await model.loadMembers() }
                }
            }
        }
        .confirmationDialog(
            pendingDeletion.map { "Slette \($0.realName)?" } ?? "Slette medlem?",
            isPresented: .init(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Slett", role: .destructive) {
                if let member = pendingDeletion {
                    pendingDeletion = nil
                    Task { await model.deleteMember(member) }
                }
            }
            Button("Avbryt", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Dette kan ikke angres.")
        }
    }

    /// A search field styled like the app's other inputs, standing in for the
    /// `.searchable` bar this screen can't use.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(TD.inactiveLabel)

            TextField(
                "",
                text: $searchText,
                prompt: Text("Søk etter navn eller e-post")
                    .foregroundStyle(TD.inactiveLabel)
            )
            .font(TD.Font.body())
            .foregroundStyle(TD.primary)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(TD.inactiveLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tøm søk")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(TD.inputBackground, in: RoundedRectangle(cornerRadius: TD.Radius.input))
        .overlay(
            RoundedRectangle(cornerRadius: TD.Radius.input)
                .strokeBorder(TD.inputBorder, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var summary: some View {
        HStack(spacing: 10) {
            Text("\(model.members.count) medlemmer")
                .font(TD.Font.subtitle())
                .foregroundStyle(TD.inactiveLabel)

            if model.unconfirmedCount > 0 {
                TDTag(
                    text: "\(model.unconfirmedCount) ubekreftet",
                    color: TD.warning
                )
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One member, with the actions the website's table offers: change role,
/// toggle status, adjust penalty, delete.
private struct MemberAdminRow: View {
    let member: Member
    let model: AdminViewModel
    let onDelete: () -> Void

    var body: some View {
        TDCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.realName)
                        .font(TD.Font.cardTitle())
                        .foregroundStyle(TD.primary)
                    Text(member.email)
                        .font(TD.Font.small())
                        .foregroundStyle(TD.cardSubtitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: 5) {
                    TDTag(text: member.role.displayName, color: TD.activeLabel)
                    TDTag(
                        text: member.status == .active ? "Aktiv" : "Inaktiv",
                        color: member.status == .active ? TD.success : TD.offPrimary
                    )
                    TDTag(text: "Kull \(member.classof)")
                    if member.penalty > 0 {
                        TDTag(text: "\(member.penalty) prikk", color: TD.warning)
                    }
                }

                HStack(spacing: 14) {
                    Menu {
                        Picker("Rolle", selection: roleBinding) {
                            ForEach(Role.assignableCases, id: \.self) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                    } label: {
                        actionLabel("Rolle", icon: "person.badge.key")
                    }

                    Menu {
                        Picker("Status", selection: statusBinding) {
                            Text("Aktiv").tag(MemberStatus.active)
                            Text("Inaktiv").tag(MemberStatus.inactive)
                        }
                    } label: {
                        actionLabel("Status", icon: "checkmark.seal")
                    }

                    Menu {
                        Picker("Prikker", selection: penaltyBinding) {
                            ForEach(0...3, id: \.self) { count in
                                Text(count == 0 ? "Ingen" : "\(count)").tag(count)
                            }
                        }
                    } label: {
                        actionLabel("Prikker", icon: "exclamationmark.triangle")
                    }

                    Spacer(minLength: 0)

                    // The API refuses to delete another admin, so the button is
                    // hidden rather than offered and then rejected.
                    if member.role != .admin {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundStyle(TD.error)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(title)
                .font(TD.Font.small())
        }
        .foregroundStyle(TD.secondary)
    }

    // Bindings drive the pickers directly: reading gives the current value,
    // writing fires the corresponding API call.

    private var roleBinding: Binding<Role> {
        Binding(
            get: { member.role },
            set: { role in
                guard role != member.role else { return }
                Task { await model.setRole(role, for: member) }
            }
        )
    }

    private var statusBinding: Binding<MemberStatus> {
        Binding(
            get: { member.status },
            set: { status in
                guard status != member.status else { return }
                Task { await model.setStatus(status, for: member) }
            }
        )
    }

    private var penaltyBinding: Binding<Int> {
        Binding(
            get: { member.penalty },
            set: { penalty in
                guard penalty != member.penalty else { return }
                Task { await model.setPenalty(penalty, for: member) }
            }
        )
    }
}

// MARK: - Events

private struct AdminEventsSection: View {
    let model: AdminViewModel

    @State private var pendingDeletion: Event?

    var body: some View {
        Group {
            if model.isLoadingEvents, model.events.isEmpty {
                VStack {
                    Spacer()
                    ProgressView().tint(TD.primary)
                    Spacer()
                }
            } else if let error = model.eventsError, model.events.isEmpty {
                ErrorStateView(message: error) { await model.loadEvents() }
            } else if model.events.isEmpty {
                EmptyStateView(
                    title: "Ingen arrangementer",
                    message: "Opprett et arrangement fra Arrangementer-fanen.",
                    icon: "calendar"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        Text("Rediger et arrangement fra Arrangementer-fanen.")
                            .font(TD.Font.small())
                            .foregroundStyle(TD.inactiveLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(model.events) { event in
                            AdminEventRow(event: event) { pendingDeletion = event }
                        }
                    }
                    .padding(16)
                }
                .refreshable { await model.loadEvents() }
            }
        }
        .confirmationDialog(
            pendingDeletion.map { "Slette «\($0.title)»?" } ?? "Slette arrangement?",
            isPresented: .init(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Slett", role: .destructive) {
                if let event = pendingDeletion {
                    pendingDeletion = nil
                    Task { await model.deleteEvent(event) }
                }
            }
            Button("Avbryt", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Dette kan ikke angres.")
        }
    }
}

private struct AdminEventRow: View {
    let event: Event
    let onDelete: () -> Void

    private var isPast: Bool { event.date < .now }

    var body: some View {
        TDCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(TD.Font.cardTitle())
                        .foregroundStyle(TD.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(event.date, format: .dateTime.day().month().year().hour().minute())
                        .font(TD.Font.small())
                        .foregroundStyle(TD.cardSubtitle)

                    HStack(spacing: 5) {
                        // Mirrors the website's active / upcoming / inactive
                        // legend on the events table.
                        TDTag(
                            text: isPast ? "Avsluttet" : "Kommende",
                            color: isPast ? TD.offPrimary : TD.success
                        )
                        if event.public == false {
                            TDTag(text: "Skjult", color: TD.warning)
                        }
                        if let max = event.maxParticipants {
                            TDTag(text: "Maks \(max)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(TD.error)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
        }
    }
}
