import Foundation

/// Mirrors a job listing from `GET /api/jobs/`.
nonisolated struct Job: Codable, Identifiable, Hashable {
    let id: UUID
    let company: String
    let title: String
    let type: String
    let tags: [String]
    let descriptionPreview: String
    let description: String
    let publishedDate: Date
    let location: String
    let link: String
    let startDate: Date?
    let dueDate: Date?

    enum CodingKeys: String, CodingKey {
        case id, company, title, type, tags, description, location, link
        case descriptionPreview = "description_preview"
        case publishedDate = "published_date"
        case startDate = "start_date"
        case dueDate = "due_date"
    }

    /// `tags` without the stray one-character entries the live data contains
    /// (e.g. a lone backtick), already capitalised for display.
    ///
    /// Computed once at decode rather than in the card's `body`, which filtered
    /// and capitalised the list again on every render of every visible row.
    let displayTags: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        company = try container.decode(String.self, forKey: .company)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decode(String.self, forKey: .type)
        tags = try container.decode([String].self, forKey: .tags)
        descriptionPreview = try container.decode(String.self, forKey: .descriptionPreview)
        description = try container.decode(String.self, forKey: .description)
        publishedDate = try container.decode(Date.self, forKey: .publishedDate)
        location = try container.decode(String.self, forKey: .location)
        link = try container.decode(String.self, forKey: .link)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)

        displayTags = tags.filter { $0.count > 1 }.map(\.capitalized)
    }

    /// `displayTags` is derived, so it is not written back to the API.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(company, forKey: .company)
        try container.encode(title, forKey: .title)
        try container.encode(type, forKey: .type)
        try container.encode(tags, forKey: .tags)
        try container.encode(descriptionPreview, forKey: .descriptionPreview)
        try container.encode(description, forKey: .description)
        try container.encode(publishedDate, forKey: .publishedDate)
        try container.encode(location, forKey: .location)
        try container.encode(link, forKey: .link)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
    }
}
