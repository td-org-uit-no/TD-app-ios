import Foundation

/// Mirrors the API's `Event` model (app/models.py).
/// Field names match the JSON exactly, so no CodingKeys are needed.
nonisolated struct Event: Codable, Identifiable, Hashable {
    let eid: UUID
    let title: String
    let date: Date
    let address: String
    let price: Int
    let description: String

    let duration: Int?
    let `public`: Bool
    let bindingRegistration: Bool
    let transportation: Bool
    let food: Bool
    let extraInformation: String?
    let maxParticipants: Int?
    let romNumber: String?
    let building: String?
    let picturePath: String?
    let registrationOpeningDate: Date?
    let confirmed: Bool?

    /// `host` and `registeredPenalties` are only present on the admin-facing
    /// `Event` model; the public `EventUserView` omits them.
    let host: String?
    let registeredPenalties: [UUID]?

    var id: UUID { eid }

    var isFree: Bool { price == 0 }

    /// Room + building, when the API has them.
    var location: String {
        [romNumber, building].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Body for `POST /api/event/{id}/join` and `PUT /api/event/{id}/update-options`.
///
/// These are non-optional on purpose. The API's own `JoinEventPayload` marks
/// every field `Optional`, but `join_event` feeds them directly into
/// `Participant`, which requires `food: bool`, `transportation: bool` and
/// `dietaryRestrictions: str`. Passing null is accepted by the request schema
/// and then blows up in validation, so the server answers 500. Keeping the
/// Swift type non-optional makes that unrepresentable.
nonisolated struct JoinEventPayload: Codable {
    var food: Bool
    var transportation: Bool
    var dietaryRestrictions: String

    init(
        food: Bool = false,
        transportation: Bool = false,
        dietaryRestrictions: String = ""
    ) {
        self.food = food
        self.transportation = transportation
        self.dietaryRestrictions = dietaryRestrictions
    }
}

/// Response shape of `GET /api/event/past-events/count`.
nonisolated struct PastEventsCount: Codable {
    let count: Int
}

/// Response shape of `GET /api/event/{id}/joined`.
/// The endpoint returns `{"joined": true}`, not a bare boolean.
nonisolated struct JoinedStatus: Codable {
    let joined: Bool
}

nonisolated extension Array where Element == Event {
    /// Removes events sharing an `eid`, keeping the first occurrence.
    ///
    /// The API can return the same event more than once — a database seeded
    /// repeatedly will serve triplicates, for instance. Because `Event.id` is
    /// `eid`, feeding those straight into a `ForEach` produces children with
    /// identical IDs, which SwiftUI reports as "the ID … is used by multiple
    /// child views, this will give undefined results!" and which corrupts
    /// `LazyVStack` layout — rows fail to appear until scrolled well past.
    func deduplicatedByID() -> [Event] {
        var seen = Set<UUID>()
        return filter { seen.insert($0.eid).inserted }
    }
}
