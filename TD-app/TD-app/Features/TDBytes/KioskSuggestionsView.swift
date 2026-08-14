import SwiftUI

/// The admin-only suggestion list, ported from the website's
/// `pages/TDBytes/ProductSuggestions.tsx`.
///
/// The site renders a Dato/Forslag/Bruker table; a phone is too narrow for
/// three columns, so each row becomes a card with the same three fields.
struct KioskSuggestionsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var suggestions: [KioskSuggestion] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pendingDeletion: KioskSuggestion?

    /// Only full admins may delete; kiosk admins can read the list only.
    private var canDelete: Bool { session.member?.role == .admin }

    var body: some View {
        ZStack(alignment: .top) {
            TDScreenBackground()

            VStack(spacing: 0) {
                TDPageHeader("Produktforslag", back: { dismiss() })
                content
            }
        }
        // The bar is hidden in favour of `TDPageHeader`, which carries the
        // title and the back action.
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .task { await load() }
        .confirmationDialog(
            "Er du sikker på at du vil slette forslaget?",
            isPresented: .init(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Slett", role: .destructive) {
                if let pendingDeletion { delete(pendingDeletion) }
            }
            Button("Avbryt", role: .cancel) { pendingDeletion = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        if suggestions.isEmpty, isLoading {
            ProgressView()
                .tint(TD.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, suggestions.isEmpty {
            Spacer()
            ErrorStateView(message: errorMessage) { await load() }
            Spacer()
        } else if suggestions.isEmpty {
            Spacer()
            EmptyStateView(
                title: "Ingen forslag",
                message: "Fant ingen forslag ennå.",
                icon: "lightbulb"
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(suggestions) { suggestion in
                        SuggestionRow(
                            suggestion: suggestion,
                            onDelete: canDelete
                                ? { pendingDeletion = suggestion }
                                : nil
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            suggestions = try await APIClient.shared.kioskSuggestions()
        } catch APIError.unauthorized {
            errorMessage = "Du har ikke de nødvendige rettighetene"
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "Noe gikk galt"
        }
    }

    private func delete(_ suggestion: KioskSuggestion) {
        pendingDeletion = nil
        Task {
            do {
                try await APIClient.shared.deleteKioskSuggestion(id: suggestion.id)
                suggestions.removeAll { $0.id == suggestion.id }
            } catch {
                errorMessage = (error as? APIError)?.errorDescription
                    ?? "En ukjent feil skjedde"
            }
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: KioskSuggestion
    /// `nil` for kiosk admins, who may read the list but not delete from it.
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.product)
                    .font(TD.Font.cardTitle())
                    .foregroundStyle(TD.primary)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 12) {
                    Label {
                        Text(suggestion.timestamp, format: .dateTime.day().month().year())
                    } icon: {
                        Image(systemName: "calendar")
                    }

                    // Kiosk admins get a literal "-" here from the API, which
                    // is noise rather than information.
                    if suggestion.username != "-" {
                        Label(suggestion.username, systemImage: "person")
                    }
                }
                .font(TD.Font.small())
                .foregroundStyle(TD.inactiveLabel)
            }

            Spacer(minLength: 4)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(TD.error)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Shadow on the shape rather than the row — see `TDCard`.
        .background {
            RoundedRectangle(cornerRadius: TD.Radius.card)
                .fill(TD.surface)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
    }
}
