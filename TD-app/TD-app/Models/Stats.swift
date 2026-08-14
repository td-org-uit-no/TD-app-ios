import Foundation

/// One point on the unique-visitors series (`GET /api/stats/unique-visit`).
///
/// The backend groups by day and returns the date as a *string* in the same
/// format it grouped on — `yyyy-MM-dd`, or `yyyy-MM-dd'T'HH` when the requested
/// range is under 48 hours and it switches to hourly buckets. It is decoded as
/// a string rather than a `Date` because `APIClient`'s date strategy targets
/// the full timestamps used elsewhere and would reject the hourly form.
nonisolated struct VisitPoint: Codable, Identifiable, Hashable {
    let date: String
    let count: Int

    var id: String { date }

    /// The bucket as a real date, for plotting. Falls back to `nil` on a format
    /// the backend hasn't used before, and such points are simply dropped.
    var parsedDate: Date? {
        for formatter in Self.formatters {
            if let parsed = formatter.date(from: date) { return parsed }
        }
        return nil
    }

    /// Built once rather than per call. `DateFormatter` is expensive to
    /// construct, and this is read for every point in the series each time the
    /// stats chart renders — which was allocating two formatters per point, per
    /// render, to parse strings that never change.
    private static let formatters: [DateFormatter] = ["yyyy-MM-dd'T'HH", "yyyy-MM-dd"]
        .map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "Europe/Oslo")
            return formatter
        }
}

/// A row of `GET /api/stats/most_visited_pages_last_month`.
///
/// `title` is resolved server-side from the path — for an event or job page it
/// is that object's title, and the backend falls back to the path itself when
/// it can't resolve one. It stays optional here so a missing key decodes rather
/// than failing the whole request.
nonisolated struct PageStat: Codable, Identifiable, Hashable {
    let path: String
    let title: String?
    let count: Int

    var id: String { path }

    /// What to show in a list row: the resolved title when there is one, else
    /// the raw path.
    var displayName: String {
        guard let title, !title.isEmpty else { return path }
        return title
    }
}
