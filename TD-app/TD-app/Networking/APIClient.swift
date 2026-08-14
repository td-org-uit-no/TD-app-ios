import Foundation

nonisolated enum APIEnvironment {
    /// The live site. Writes here are real: joining an event puts you on the
    /// actual attendee list that td-uit.no shows.
    case production
    /// TD's shared dev server. Only reachable from inside TD's network.
    case development

    var baseURL: URL {
        switch self {
        case .production:  URL(string: "https://api.td-uit.no")!
        case .development:       URL(string: "http://localhost:5001")!
        }
    }

    /// The active environment.
    ///
    /// `.local` talks to the tdctl-api container (`./dev_utils.sh compose up -d`
    /// in ~/Documents/Coding/tdctl-api), seeded with `./dev_utils.sh seed`.
    /// Log in there as dev_admin@admin.com / Admin!234.
    ///
    /// Switch to `.production` to hit the real site — note that joining an
    /// event there puts you on the actual attendee list.
    static let current: APIEnvironment = .development
}

nonisolated enum APIError: LocalizedError {
    case unauthorized
    case notFound
    case server(status: Int, detail: String?)
    case decoding(underlying: Error)
    case transport(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "You need to log in to do that."
        case .notFound:
            "Not found."
        case let .server(status, detail):
            // A 500 body is Starlette's HTML error page, so `detail` is nil and
            // the raw status alone tells the user nothing actionable.
            detail ?? (status >= 500
                ? "The server ran into a problem (\(status)). Please try again."
                : "The server returned an error (\(status)).")
        case .decoding:
            "The server sent something the app didn't understand."
        case let .transport(error):
            error.localizedDescription
        }
    }
}

/// The API's error bodies are FastAPI-shaped: `{"detail": "..."}`.
/// `detail` can also be a validation-error array, which we ignore.
private nonisolated struct APIErrorBody: Decodable {
    let detail: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        detail = try? container.decode(String.self, forKey: .detail)
    }

    enum CodingKeys: String, CodingKey { case detail }
}

private nonisolated enum HTTPMethod: String {
    case get = "GET", post = "POST", put = "PUT", delete = "DELETE"
}

/// Talks to the tdctl-api backend.
///
/// Auth note: the backend authenticates with **httpOnly cookies**
/// (`access_token` / `refresh_token` set by `POST /api/auth/login`), not with
/// bearer headers. We therefore let URLSession's cookie storage carry
/// credentials automatically, and only need to handle the token *refresh*
/// dance ourselves via `POST /api/auth/renew`.
actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession

    /// Guards against a stampede of parallel `/renew` calls when several
    /// requests get a 401 at the same time.
    private var activeRenewal: Task<Bool, Never>?

    init(environment: APIEnvironment = .current) {
        self.baseURL = environment.baseURL

        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Coding

    /// The API emits naive ISO-8601 timestamps with no timezone suffix
    /// (e.g. `2026-06-05T18:00:00`), sometimes with fractional seconds
    /// (`...:44.635000`). `.iso8601` rejects both, so we parse by hand and
    /// interpret them in the club's local timezone (Tromsø).
    private static let decoder: JSONDecoder = {
        let formatters: [DateFormatter] = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd",
        ].map { format in
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "Europe/Oslo")
            return f
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            // Tolerate a trailing Z / offset if the backend ever adds one.
            let trimmed = raw.hasSuffix("Z") ? String(raw.dropLast()) : raw

            // Pick the formatter by shape instead of trying each in turn.
            //
            // `DateFormatter.date(from:)` is an expensive ICU parse, and every
            // event and job carries two or three date fields. Walking the list
            // meant the common `...T18:00:00` form paid two *failed* parses —
            // the fractional-second formats are listed first — before the one
            // that works. The length of the string identifies the format
            // unambiguously here, so one parse is enough.
            let formatter: DateFormatter? = switch trimmed.count {
            case 26: formatters[0]  // yyyy-MM-dd'T'HH:mm:ss.SSSSSS
            case 23: formatters[1]  // yyyy-MM-dd'T'HH:mm:ss.SSS
            case 19: formatters[2]  // yyyy-MM-dd'T'HH:mm:ss
            case 10: formatters[3]  // yyyy-MM-dd
            default: nil
            }
            if let date = formatter?.date(from: trimmed) { return date }

            // An unexpected shape, or a value that didn't parse as the shape
            // suggested: fall back to trying everything before giving up, so
            // this stays no stricter than it was.
            for formatter in formatters {
                if let date = formatter.date(from: trimmed) { return date }
            }
            if let date = ISO8601DateFormatter().date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unrecognised date format: \(raw)"
            )
        }
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Oslo")
        encoder.dateEncodingStrategy = .formatted(formatter)
        return encoder
    }()

    // MARK: - Core request

    @discardableResult
    private func send<Response: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (some Encodable)? = Optional<Never>.none,
        as type: Response.Type = Response.self,
        allowRetry: Bool = true
    ) async throws -> Response {
        let data = try await sendRaw(
            method, path, query: query, body: body, allowRetry: allowRetry
        )

        // Endpoints that return no content decode as EmptyResponse.
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error)
        }
    }

    @discardableResult
    private func sendRaw(
        _ method: HTTPMethod,
        _ path: String,
        query: [URLQueryItem] = [],
        body: (some Encodable)? = Optional<Never>.none,
        allowRetry: Bool = true
    ) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try Self.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, detail: nil)
        }

        switch http.statusCode {
        case 200..<300:
            return data

        case 401:
            // Try once to refresh the session, then replay the request.
            guard allowRetry, await renewSession() else {
                throw APIError.unauthorized
            }
            return try await sendRaw(
                method, path, query: query, body: body, allowRetry: false
            )

        case 404:
            throw APIError.notFound

        default:
            let detail = try? Self.decoder.decode(APIErrorBody.self, from: data).detail
            throw APIError.server(status: http.statusCode, detail: detail)
        }
    }

    /// Posts a pre-built multipart body, retrying once through `/renew` on a
    /// 401 exactly like `sendRaw` does.
    ///
    /// This can't go through `sendRaw`, which always encodes its body as JSON.
    private func sendMultipart(
        _ path: String,
        body: Data,
        boundary: String,
        allowRetry: Bool = true
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, detail: nil)
        }

        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            guard allowRetry, await renewSession() else { throw APIError.unauthorized }
            try await sendMultipart(
                path, body: body, boundary: boundary, allowRetry: false
            )
        case 413:
            throw APIError.server(status: 413, detail: "Bildet er for stort.")
        default:
            let detail = try? Self.decoder.decode(APIErrorBody.self, from: data).detail
            throw APIError.server(status: http.statusCode, detail: detail)
        }
    }

    // MARK: - Auth

    /// Logs in. Cookies are stored by URLSession, so there is no token to keep.
    func login(email: String, password: String) async throws {
        let credentials = Credentials(email: email.lowercased(), password: password)
        try await send(
            .post, "api/auth/login", body: credentials, as: EmptyResponse.self,
            // A 401 here means bad credentials, not an expired session.
            allowRetry: false
        )
    }

    func logout() async {
        _ = try? await sendRaw(.post, "api/auth/logout", allowRetry: false)
        clearCookies()
    }

    /// Exchanges the refresh cookie for a fresh pair. Returns whether it worked.
    private func renewSession() async -> Bool {
        if let activeRenewal { return await activeRenewal.value }

        let task = Task<Bool, Never> {
            do {
                _ = try await sendRaw(.post, "api/auth/renew", allowRetry: false)
                return true
            } catch {
                clearCookies()
                return false
            }
        }
        activeRenewal = task
        let result = await task.value
        activeRenewal = nil
        return result
    }

    private func clearCookies() {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) else { return }
        for cookie in cookies { HTTPCookieStorage.shared.deleteCookie(cookie) }
    }

    /// A refresh cookie existing is a hint that we *may* still be logged in;
    /// `currentMember()` is the real check.
    var hasStoredSession: Bool {
        HTTPCookieStorage.shared.cookies(for: baseURL)?
            .contains { $0.name == "refresh_token" } ?? false
    }

    /// Registers a new member.
    ///
    /// The account is created with role `unconfirmed` and status `inactive`;
    /// the backend then mails a confirmation link — but *only* when the server
    /// runs with `ENV == 'production'`. Against `.local` or `.development` the
    /// account is still created, the mail simply never arrives, so the caller
    /// should not promise an e-mail unconditionally.
    ///
    /// The endpoint answers 409 when the address is taken and 400 when the
    /// password fails the strength rules; both surface as `APIError.server`
    /// carrying the backend's `detail`. Retrying a 401 makes no sense on a
    /// no-auth route, hence `allowRetry: false`.
    func register(_ member: MemberInput) async throws {
        try await send(
            .post, "api/member/", body: member, as: EmptyResponse.self,
            allowRetry: false
        )
    }

    /// Asks the backend to mail a password-reset link to `email`.
    ///
    /// The link points at the *website* (`FRONTEND_URL/reset-password/{code}`),
    /// so the reset itself is finished in a browser — there is no in-app step
    /// that follows this one. The code expires after 10 minutes (`db.py` sets a
    /// TTL index on `passwordResets`).
    ///
    /// Answers 404 when no member has that address. Callers should *not* relay
    /// that distinction to the user: it would turn the screen into an oracle
    /// for which addresses are registered.
    ///
    /// Note the backend matches `email` verbatim rather than lowercasing it, so
    /// the caller must send the address in the same case it was registered with.
    func requestPasswordReset(email: String) async throws {
        let escaped = email.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? email
        try await send(
            .post, "api/member/reset-password/code/\(escaped)",
            as: EmptyResponse.self, allowRetry: false
        )
    }

    // MARK: - Members

    func currentMember() async throws -> Member {
        try await send(.get, "api/member/")
    }

    func updateMember(_ update: MemberUpdate) async throws {
        try await send(.put, "api/member/", body: update, as: EmptyResponse.self)
    }

    /// Changes the logged-in member's password.
    ///
    /// The endpoint lives under `/auth`, not `/member`. It answers 403 when
    /// `current` doesn't match and 400 when `new` fails the server's strength
    /// rules; both arrive as `APIError.server` carrying the backend's `detail`.
    /// Retrying a 401 is pointless here — the cookie is fine, it's the password
    /// that's being checked — but a genuinely expired access token should still
    /// renew, so the default retry behaviour is left alone.
    func changePassword(current: String, new: String) async throws {
        try await send(
            .post, "api/auth/password",
            body: PasswordChange(password: current, newPassword: new),
            as: EmptyResponse.self
        )
    }

    // MARK: - Admin
    //
    // Everything below requires the admin role; the backend answers 401 for
    // anyone else, which surfaces as `APIError.unauthorized`.

    /// Every member. Note the path is `api/members/` — the route is registered
    /// as `"s/"` on the `/api/member` prefix, so the plural is deliberate.
    func allMembers() async throws -> [Member] {
        try await send(.get, "api/members/", as: [Member].self)
    }

    func adminUpdateMember(id: UUID, update: AdminMemberUpdate) async throws {
        try await send(
            .put, "api/admin/member/\(id.uuidString.lowercased())",
            body: update, as: EmptyResponse.self
        )
    }

    /// Deletes a member. The backend refuses (403) when the target is an admin.
    func deleteMember(id: UUID) async throws {
        try await send(
            .delete, "api/admin/member/\(id.uuidString.lowercased())",
            as: EmptyResponse.self
        )
    }

    /// Sets a member's penalty count outright — this is an assignment, not an
    /// increment, so `0` clears it.
    func setPenalty(memberID: UUID, penalty: Int) async throws {
        try await send(
            .post, "api/admin/assign-penalty-to-member/\(memberID.uuidString.lowercased())",
            body: PenaltyInput(penalty: penalty), as: EmptyResponse.self
        )
    }

    func giveAdminPrivileges(memberID: UUID) async throws {
        try await send(
            .post, "api/admin/give-admin-privileges/\(memberID.uuidString.lowercased())",
            as: EmptyResponse.self
        )
    }

    // MARK: - Stats

    /// Unique visitors per day. The API returns an empty array when nothing has
    /// been logged yet, which is a valid "no data" answer rather than an error.
    ///
    /// `start`/`end` are sent in the backend's expected
    /// `yyyy-MM-dd HH:mm:ss` form, which is *not* the ISO format used for
    /// event payloads, hence the dedicated formatter.
    func uniqueVisits(from start: Date? = nil, to end: Date? = nil) async throws -> [VisitPoint] {
        var query: [URLQueryItem] = []
        if let start {
            query.append(URLQueryItem(name: "start", value: Self.statsDateFormatter.string(from: start)))
        }
        if let end {
            query.append(URLQueryItem(name: "end", value: Self.statsDateFormatter.string(from: end)))
        }
        return try await send(
            .get, "api/stats/unique-visit", query: query, as: [VisitPoint].self
        )
    }

    /// The five most-visited pages over the last four weeks.
    func mostVisitedPages() async throws -> [PageStat] {
        try await send(
            .get, "api/stats/most_visited_pages_last_month", as: [PageStat].self
        )
    }

    private static let statsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Oslo")
        return formatter
    }()

    // MARK: - Events

    // Event listings are deduplicated here rather than in each view: the API
    // can return the same event several times, and duplicate `eid`s break
    // SwiftUI's `ForEach` identity.

    func upcomingEvents() async throws -> [Event] {
        try await send(.get, "api/event/upcoming", as: [Event].self)
            .deduplicatedByID()
    }

    /// One page of past events, newest first.
    ///
    /// The endpoint takes **only** `skip` — page size is hardcoded to 10 on the
    /// server (`fixed_limit`), and a `limit` query parameter is ignored. Hence
    /// `EventsViewModel.pageSize` must stay in sync with `Self.pastEventsPageSize`.
    func pastEvents(skip: Int = 0) async throws -> [Event] {
        try await pastEventsPage(skip: skip).events
    }

    /// A page of past events together with the number of rows the server sent.
    ///
    /// Pagination needs the *raw* row count: the server skips over documents,
    /// but `deduplicatedByID()` can shrink a page below the 10 rows it actually
    /// returned. Advancing `skip` by the deduplicated count would then re-request
    /// rows already seen. Callers that paginate must use `rowCount`, not
    /// `events.count`.
    func pastEventsPage(skip: Int = 0) async throws -> (events: [Event], rowCount: Int) {
        let raw = try await send(.get, "api/event/past-events", query: [
            URLQueryItem(name: "skip", value: String(skip)),
        ], as: [Event].self)

        return (raw.deduplicatedByID(), raw.count)
    }

    /// The server's fixed page size for `pastEvents(skip:)`.
    static let pastEventsPageSize = 10

    /// Every past event, fetched page by page.
    ///
    /// For callers that need the whole list rather than a scrollable window —
    /// the admin table in particular. `pastEvents(skip:)` serves a single
    /// 10-row page, so asking for it once yields only the ten most recent.
    ///
    /// `skip` advances by the raw row count for the reason `pastEventsPage`
    /// documents, and the loop stops on the first empty page rather than
    /// trusting the count endpoint, so a disagreement between the two can't
    /// spin here forever.
    func allPastEvents() async throws -> [Event] {
        var collected: [Event] = []
        var seen: Set<UUID> = []
        var skip = 0

        while true {
            let (events, rowCount) = try await pastEventsPage(skip: skip)
            guard rowCount > 0 else { break }
            skip += rowCount

            for event in events where seen.insert(event.eid).inserted {
                collected.append(event)
            }
        }

        return collected
    }

    func pastEventsCount() async throws -> Int {
        try await send(.get, "api/event/past-events/count", as: PastEventsCount.self).count
    }

    func event(id: UUID) async throws -> Event {
        try await send(.get, "api/event/\(id.uuidString.lowercased())")
    }

    /// Events the logged-in member has signed up for.
    func joinedEvents() async throws -> [Event] {
        try await send(.get, "api/event/joined-events", as: [Event].self)
            .deduplicatedByID()
    }

    /// Whether the logged-in member is on this event's participant list.
    /// The endpoint wraps the flag in an object: `{"joined": true}`.
    func isJoined(eventID: UUID) async throws -> Bool {
        try await send(
            .get, "api/event/\(eventID.uuidString.lowercased())/joined",
            as: JoinedStatus.self
        ).joined
    }

    func join(eventID: UUID, options: JoinEventPayload) async throws {
        try await send(
            .post, "api/event/\(eventID.uuidString.lowercased())/join",
            body: options, as: EmptyResponse.self
        )
    }

    // MARK: Event administration

    /// Creates an event and returns its new id. Admin only.
    ///
    /// The id is needed to upload the poster, which is a separate request —
    /// there is no way to create an event and its image in one call.
    @discardableResult
    func createEvent(_ event: EventInput) async throws -> UUID {
        let created = try await send(
            .post, "api/event/", body: event, as: CreatedEvent.self
        )
        guard let id = created.uuid else {
            throw APIError.decoding(
                underlying: DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Malformed event id")
                )
            )
        }
        return id
    }

    /// Uploads an event poster as `multipart/form-data`. Admin only.
    ///
    /// The backend writes whatever it receives to `{uuid}.png`, so a PNG is the
    /// only format that round-trips correctly even though it accepts any
    /// `image/*` content type.
    ///
    /// Callers must invalidate `ImageStore` afterwards: the poster lives at a
    /// fixed per-event URL, so a replacement is invisible while the old copy is
    /// still cached. That isn't done here because `ImageStore` is main-actor
    /// isolated and this is an actor method.
    func uploadEventImage(id: UUID, pngData: Data) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; name=\"image\"; filename=\"event.png\"\r\n"
        )
        body.appendUTF8("Content-Type: image/png\r\n\r\n")
        body.append(pngData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        try await sendMultipart(
            "api/event/\(id.uuidString.lowercased())/image",
            body: body,
            boundary: boundary
        )
    }

    /// Applies a partial update. Admin only.
    ///
    /// `EventUpdate` encodes only the fields that changed — see its definition
    /// for why sending nulls would be actively harmful here.
    func updateEvent(id: UUID, update: EventUpdate) async throws {
        try await send(
            .put, "api/event/\(id.uuidString.lowercased())",
            body: update, as: EmptyResponse.self
        )
    }

    /// Deletes an event. Admin only.
    func deleteEvent(id: UUID) async throws {
        try await send(
            .delete, "api/event/\(id.uuidString.lowercased())",
            as: EmptyResponse.self
        )
    }

    func leave(eventID: UUID) async throws {
        try await send(
            .post, "api/event/\(eventID.uuidString.lowercased())/leave",
            as: EmptyResponse.self
        )
    }

    /// URL for an event's image.
    ///
    /// Note: we deliberately do *not* check `picturePath` here. The backend's
    /// `GET /{id}/image` ignores that DB field and simply looks for
    /// `{uuid.hex}.png` on disk, so events serve real images even though the
    /// API reports `picturePath: null`. Gating on the field hides every image.
    /// Callers handle the 404 case by falling back to a placeholder.
    nonisolated func eventImageURL(for event: Event) -> URL {
        eventImageURL(forEventID: event.eid)
    }

    nonisolated func eventImageURL(forEventID id: UUID) -> URL {
        baseURL.appendingPathComponent(
            "api/event/\(id.uuidString.lowercased())/image"
        )
    }

    // MARK: - Jobs

    func jobs() async throws -> [Job] {
        try await send(.get, "api/jobs/")
    }

    /// One listing, re-read after an admin edits it.
    func job(id: UUID) async throws -> Job {
        try await send(.get, "api/jobs/\(id.uuidString.lowercased())")
    }

    /// URL for a job's company logo.
    ///
    /// The job JSON carries no image field — like events, the picture lives
    /// behind its own route. Production serves a PNG for every listing; the
    /// seeded local database has none, so callers fall back to a placeholder
    /// on the 404.
    nonisolated func jobImageURL(for job: Job) -> URL {
        baseURL.appendingPathComponent(
            "api/jobs/\(job.id.uuidString.lowercased())/image"
        )
    }

    // MARK: Job administration

    /// Creates a job listing and returns its new id. Admin only.
    ///
    /// As with events, the id is needed to upload the company logo, which is a
    /// separate request.
    @discardableResult
    func createJob(_ job: JobInput) async throws -> UUID {
        let created = try await send(
            .post, "api/jobs/", body: job, as: CreatedJob.self
        )
        guard let id = created.uuid else {
            throw APIError.decoding(
                underlying: DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Malformed job id")
                )
            )
        }
        return id
    }

    /// Applies a partial update. Admin only.
    ///
    /// `JobUpdate` encodes only the fields that changed — see its definition for
    /// why sending nulls indiscriminately would be harmful here.
    func updateJob(id: UUID, update: JobUpdate) async throws {
        try await send(
            .put, "api/jobs/\(id.uuidString.lowercased())",
            body: update, as: EmptyResponse.self
        )
    }

    /// Deletes a job listing. Admin only.
    func deleteJob(id: UUID) async throws {
        try await send(
            .delete, "api/jobs/\(id.uuidString.lowercased())",
            as: EmptyResponse.self
        )
    }

    /// Uploads a company logo as `multipart/form-data`. Admin only.
    ///
    /// Like the event poster, the backend writes whatever it receives to
    /// `{uuid}.png`, so only a PNG round-trips correctly.
    ///
    /// Callers must invalidate `ImageStore` afterwards: the logo lives at a
    /// fixed per-job URL, so a replacement is invisible while the old copy is
    /// still cached.
    func uploadJobImage(id: UUID, pngData: Data) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8(
            "Content-Disposition: form-data; name=\"image\"; filename=\"job.png\"\r\n"
        )
        body.appendUTF8("Content-Type: image/png\r\n\r\n")
        body.append(pngData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        try await sendMultipart(
            "api/jobs/\(id.uuidString.lowercased())/image",
            body: body,
            boundary: boundary
        )
    }

    // MARK: - Kiosk (TD Bytes)

    /// Suggests a product for the kiosk to stock. Requires a logged-in member.
    func suggestProduct(_ product: String) async throws {
        try await send(
            .post, "api/kiosk/suggestion",
            body: KioskSuggestionPayload(product: product),
            as: EmptyResponse.self
        )
    }

    /// Every suggestion, newest first. Requires the kiosk-admin or admin role;
    /// anyone else gets a 401.
    ///
    /// The endpoint raises a 404 when the collection is empty rather than
    /// returning `[]`, so that case is translated back into an empty list here
    /// — "nobody has suggested anything yet" is not an error.
    func kioskSuggestions() async throws -> [KioskSuggestion] {
        do {
            return try await send(.get, "api/kiosk/suggestions", as: [KioskSuggestion].self)
                .sorted { $0.timestamp > $1.timestamp }
        } catch APIError.notFound {
            return []
        }
    }

    /// Deletes a suggestion. Admin only.
    func deleteKioskSuggestion(id: UUID) async throws {
        try await send(
            .delete, "api/kiosk/suggestion/\(id.uuidString.lowercased())",
            as: EmptyResponse.self
        )
    }
}

/// Placeholder for endpoints that return no meaningful body.
nonisolated struct EmptyResponse: Decodable {}

/// Response of `POST /api/event/`.
///
/// The backend returns `uuid4().hex` — 32 unhyphenated characters — which
/// `UUID(uuidString:)` refuses, so the dashes are reinserted before parsing.
nonisolated struct CreatedEvent: Decodable {
    let eid: String

    var uuid: UUID? { UUID(hexOrDashed: eid) }
}

/// Response of `POST /api/jobs/`.
///
/// Returns the new job's `uuid4().hex` under `id`, in the same unhyphenated
/// form as `CreatedEvent`.
nonisolated struct CreatedJob: Decodable {
    let id: String

    var uuid: UUID? { UUID(hexOrDashed: id) }
}

private extension UUID {
    /// Parses a UUID that may arrive either dashed or as 32 bare hex digits,
    /// which is how the API returns freshly created ids.
    ///
    /// `nonisolated` because the callers are the `nonisolated` decoded
    /// responses above; this is pure string parsing over its argument and
    /// touches no shared state, so it has no reason to be actor-bound.
    nonisolated init?(hexOrDashed string: String) {
        if let direct = UUID(uuidString: string) {
            self = direct
            return
        }

        let hex = string.replacingOccurrences(of: "-", with: "")
        guard hex.count == 32 else { return nil }

        var formatted = ""
        for (offset, character) in hex.enumerated() {
            if [8, 12, 16, 20].contains(offset) { formatted.append("-") }
            formatted.append(character)
        }
        guard let parsed = UUID(uuidString: formatted) else { return nil }
        self = parsed
    }
}

private extension Data {
    /// Appends UTF-8 text, for assembling multipart bodies.
    ///
    /// `nonisolated` because the target defaults to main-actor isolation, which
    /// this would otherwise inherit — and it is called from `APIClient`, which
    /// is an actor of its own.
    nonisolated mutating func appendUTF8(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
