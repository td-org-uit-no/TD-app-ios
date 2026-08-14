import Foundation

/// Body for `PUT /api/admin/member/{id}`.
///
/// Like the member-facing update, the backend applies only truthy values —
/// except `penalty`, which it special-cases so that `0` (clearing someone's
/// prikker) does get written.
nonisolated struct AdminMemberUpdate: Codable {
    var realName: String?
    var role: Role?
    var status: MemberStatus?
    var email: String?
    var classof: String?
    var phone: String?
    var penalty: Int?
}

/// Body for `POST /api/admin/assign-penalty-to-member/{id}`.
nonisolated struct PenaltyInput: Codable {
    let penalty: Int
}

/// Body for `PUT /api/event/{id}`.
///
/// The endpoint dumps with `exclude_unset=True` and then re-validates the
/// merged event, so a key present with a `null` value is treated as *clearing*
/// that field — and clearing a required one answers 400. Swift's synthesised
/// encoder writes `null` for every nil optional, which would do exactly that,
/// so `encode(to:)` is written by hand to emit only the fields that were set.
nonisolated struct EventUpdate: Codable {
    var title: String?
    var date: Date?
    var address: String?
    var description: String?
    var maxParticipants: Int?
    var `public`: Bool?
    var price: Int?
    var transportation: Bool?
    var food: Bool?
    var registrationOpeningDate: Date?
    var confirmed: Bool?

    enum CodingKeys: String, CodingKey {
        case title, date, address, description, maxParticipants
        case `public`, price, transportation, food
        case registrationOpeningDate, confirmed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // `encodeIfPresent` is the whole point here: it omits nil keys rather
        // than writing an explicit null.
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(maxParticipants, forKey: .maxParticipants)
        try container.encodeIfPresent(`public`, forKey: .public)
        try container.encodeIfPresent(price, forKey: .price)
        try container.encodeIfPresent(transportation, forKey: .transportation)
        try container.encodeIfPresent(food, forKey: .food)
        try container.encodeIfPresent(
            registrationOpeningDate, forKey: .registrationOpeningDate
        )
        try container.encodeIfPresent(confirmed, forKey: .confirmed)
    }

    /// Whether anything would actually be sent. The API rejects an empty update
    /// with a 400, so callers check this first.
    var isEmpty: Bool {
        title == nil && date == nil && address == nil && description == nil
            && maxParticipants == nil && `public` == nil && price == nil
            && transportation == nil && food == nil
            && registrationOpeningDate == nil && confirmed == nil
    }
}

/// Body for `POST /api/jobs/`.
///
/// Mirrors the API's `JobItemPayload`, where every field except the two dates
/// is required — a missing one is a 422.
///
/// `publishedDate` is required by the payload model but the endpoint overwrites
/// it with `datetime.now()` on insert, so what we send is never stored. The
/// website sends `new Date()` for it; this does the same rather than leave out
/// a field the validator demands.
nonisolated struct JobInput: Codable {
    var company: String
    var title: String
    var type: String
    var tags: [String]
    var descriptionPreview: String
    var description: String
    var publishedDate: Date
    var location: String
    var link: String
    var startDate: Date?
    var dueDate: Date?

    enum CodingKeys: String, CodingKey {
        case company, title, type, tags, description, location, link
        case descriptionPreview = "description_preview"
        case publishedDate = "published_date"
        case startDate = "start_date"
        case dueDate = "due_date"
    }
}

/// Body for `PUT /api/jobs/{id}`.
///
/// Same contract as `EventUpdate`: the endpoint dumps with `exclude_unset=True`
/// and re-validates the merged job, so a key present with a `null` value clears
/// that field — and clearing a required one answers 400. The synthesised
/// encoder would write `null` for every nil optional, so `encode(to:)` is
/// hand-written to emit only what was set.
///
/// The two dates are the exception: they're optional on `JobItem` itself, so
/// sending an explicit null is the only way to *remove* a deadline. That needs
/// a third state beyond "unchanged" and "set to a value", which
/// `DateFieldUpdate` provides.
nonisolated struct JobUpdate: Encodable {
    /// How one of the two optional date fields should be written.
    enum DateFieldUpdate: Equatable {
        /// Leave the stored value alone — the key is omitted entirely.
        case unchanged
        /// Write a new value.
        case set(Date)
        /// Send an explicit null, clearing the stored value.
        case cleared
    }

    var company: String?
    var title: String?
    var type: String?
    var tags: [String]?
    var descriptionPreview: String?
    var description: String?
    var location: String?
    var link: String?
    var startDate: DateFieldUpdate = .unchanged
    var dueDate: DateFieldUpdate = .unchanged

    enum CodingKeys: String, CodingKey {
        case company, title, type, tags, description, location, link
        case descriptionPreview = "description_preview"
        case startDate = "start_date"
        case dueDate = "due_date"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(company, forKey: .company)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(descriptionPreview, forKey: .descriptionPreview)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(link, forKey: .link)
        try encode(startDate, forKey: .startDate, into: &container)
        try encode(dueDate, forKey: .dueDate, into: &container)
    }

    private func encode(
        _ field: DateFieldUpdate,
        forKey key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch field {
        case .unchanged: break
        case .set(let date): try container.encode(date, forKey: key)
        case .cleared: try container.encodeNil(forKey: key)
        }
    }

    /// Whether anything would actually be sent. The API rejects an empty update
    /// with a 400, so callers check this first.
    var isEmpty: Bool {
        company == nil && title == nil && type == nil && tags == nil
            && descriptionPreview == nil && description == nil
            && location == nil && link == nil
            && startDate == .unchanged && dueDate == .unchanged
    }
}

/// Body for `POST /api/event/`.
///
/// Unlike `EventUpdate`, every required field is non-optional: the backend
/// validates against `EventInput`, so a missing title or date is a 422.
///
/// The fields here mirror the website's create-event form exactly. The API's
/// own `EventInput` also accepts `duration`, `extraInformation`, `romNumber`
/// and `building`, but the site never sends them, so they're left out rather
/// than shown as fields nobody fills in.
nonisolated struct EventInput: Codable {
    var title: String
    var date: Date
    var address: String
    var price: Int
    var description: String
    var `public`: Bool
    var bindingRegistration: Bool
    var transportation: Bool
    var food: Bool
    var maxParticipants: Int?
    var registrationOpeningDate: Date?
}
