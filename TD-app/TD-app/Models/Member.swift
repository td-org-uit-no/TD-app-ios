import Foundation

nonisolated enum Role: String, Codable, CaseIterable {
    case admin
    case member
    case unconfirmed
    case kioskAdmin = "kiosk_admin"

    var displayName: String {
        switch self {
        case .admin: "Admin"
        case .member: "Medlem"
        case .unconfirmed: "Ubekreftet"
        case .kioskAdmin: "Kioskadmin"
        }
    }

    /// Roles an admin can assign from the members table.
    ///
    /// `unconfirmed` is excluded on purpose: it means "has not clicked the
    /// confirmation link yet", so setting it by hand would misrepresent an
    /// account rather than change anything real.
    static let assignableCases: [Role] = [.member, .kioskAdmin, .admin]
}

nonisolated enum MemberStatus: String, Codable {
    case active
    case inactive
}

/// Mirrors the API's `Member` model — what `GET /api/member/` returns
/// for the logged-in user.
nonisolated struct Member: Codable, Identifiable, Hashable {
    let id: UUID
    let realName: String
    let email: String
    let classof: String
    let graduated: Bool
    let phone: String?
    let role: Role
    let status: MemberStatus
    let penalty: Int

    var isAdmin: Bool { role == .admin }
}

/// Body for `POST /api/auth/login`.
nonisolated struct Credentials: Codable {
    let email: String
    let password: String
}

nonisolated extension String {
    /// Whether this looks like an e-mail address: something before and after a
    /// single `@`, with a dot in the domain that isn't the last character.
    ///
    /// Mirrors the backend's `EmailStr` loosely — precise validation is the
    /// server's job, and this only exists so a typo surfaces as the user types
    /// rather than after a round trip. The sign-up, profile-edit and
    /// forgot-password forms all check the same way, so the rule lives here
    /// rather than being restated in each of them.
    ///
    /// Expects an already-trimmed value; the forms trim before calling.
    var looksLikeEmail: Bool {
        let parts = split(separator: "@")
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        return parts[1].contains(".") && !parts[1].hasSuffix(".")
    }
}

/// Body for `PUT /api/member/`. Only non-nil fields are applied.
///
/// Note the backend is stricter than "non-nil": `update_member` skips every
/// falsy value, so an empty string is ignored rather than stored. A field
/// therefore cannot be *cleared* through this endpoint — only changed.
nonisolated struct MemberUpdate: Codable {
    var realName: String?
    var email: String?
    var classof: String?
    var phone: String?

    /// Whether this update would actually change anything on the server.
    var isEmpty: Bool {
        [realName, email, classof, phone]
            .allSatisfy { $0?.isEmpty ?? true }
    }
}

/// Body for `POST /api/auth/password`.
nonisolated struct PasswordChange: Codable {
    /// The member's current password, re-checked server-side.
    let password: String
    let newPassword: String
}

/// Body for `POST /api/member/` — registering a new member.
///
/// Mirrors the backend's `MemberInput`. Every field except `phone` is required.
/// The server assigns `role: unconfirmed` and `status: inactive` itself, so
/// there is nothing to send for those: a new account is inert until the
/// confirmation link in the welcome e-mail is opened.
nonisolated struct MemberInput: Codable {
    let realName: String
    let email: String
    let password: String
    let classof: String
    let graduated: Bool
    let phone: String?
}
