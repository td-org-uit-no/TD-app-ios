import Foundation

/// Body for `POST /api/kiosk/suggestion`.
///
/// The backend normalises the text (`product.lower().capitalize()`) before
/// storing it, so what comes back from `/suggestions` won't match the casing
/// that was sent.
nonisolated struct KioskSuggestionPayload: Codable {
    let product: String
}

/// A row from `GET /api/kiosk/suggestions` — kiosk-admin only.
///
/// `username` is the suggester's real name for admins, and a literal `"-"` for
/// kiosk admins, who are deliberately not shown who suggested what.
nonisolated struct KioskSuggestion: Codable, Identifiable, Hashable {
    let id: UUID
    let product: String
    let username: String
    let timestamp: Date
}
