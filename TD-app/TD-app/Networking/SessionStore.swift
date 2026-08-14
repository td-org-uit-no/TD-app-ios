import Foundation

/// App-wide auth state. Views observe this to decide what to show.
@MainActor
@Observable
final class SessionStore {
    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(Member)
    }

    private(set) var state: State = .unknown
    private(set) var isWorking = false
    var loginError: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    var member: Member? {
        if case let .signedIn(member) = state { return member }
        return nil
    }

    var isSignedIn: Bool { member != nil }

    /// Called on launch: if a refresh cookie survived, try to use it.
    func restore() async {
        guard await api.hasStoredSession else {
            state = .signedOut
            return
        }
        do {
            state = .signedIn(try await api.currentMember())
        } catch {
            state = .signedOut
        }
    }

    func logIn(email: String, password: String) async {
        isWorking = true
        loginError = nil
        defer { isWorking = false }

        do {
            try await api.login(email: email, password: password)
            state = .signedIn(try await api.currentMember())
        } catch {
            loginError = (error as? APIError)?.errorDescription
                ?? error.localizedDescription
            state = .signedOut
        }
    }

    /// Registers a new member and signs them straight in.
    ///
    /// The backend creates the account as `unconfirmed`/`inactive` and only the
    /// e-mail confirmation link promotes it to a full `member`. Logging in is
    /// still allowed in that state — `POST /auth/login` even flips the status to
    /// active — so signing the user in here gives them a usable session
    /// immediately, with the role left `unconfirmed` until they follow the link.
    ///
    /// Throws so the signup form can stay open and show why; `loginError` is
    /// deliberately not reused for this.
    func register(_ member: MemberInput) async throws {
        isWorking = true
        defer { isWorking = false }

        try await api.register(member)
        try await api.login(email: member.email, password: member.password)
        state = .signedIn(try await api.currentMember())
    }

    /// Asks the backend to mail a reset link. See `APIClient.requestPasswordReset`
    /// — the reset is completed on the website, not in the app.
    func requestPasswordReset(email: String) async throws {
        isWorking = true
        defer { isWorking = false }

        try await api.requestPasswordReset(email: email)
    }

    func logOut() async {
        await api.logout()
        state = .signedOut
    }

    func refreshMember() async {
        guard isSignedIn, let member = try? await api.currentMember() else { return }
        state = .signedIn(member)
    }

    /// Saves profile changes, then re-reads the member so the UI shows what the
    /// server actually stored rather than what we optimistically sent.
    ///
    /// Throws on failure so the editing view can keep the sheet open and show
    /// the reason; `loginError` is deliberately not reused for this.
    func updateMember(_ update: MemberUpdate) async throws {
        guard isSignedIn else { throw APIError.unauthorized }
        isWorking = true
        defer { isWorking = false }

        try await api.updateMember(update)
        await refreshMember()
    }

    /// Changes the password. The backend keeps the existing session valid, so
    /// there's nothing to re-authenticate afterwards.
    func changePassword(current: String, new: String) async throws {
        guard isSignedIn else { throw APIError.unauthorized }
        isWorking = true
        defer { isWorking = false }

        try await api.changePassword(current: current, new: new)
    }
}
