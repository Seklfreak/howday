import Foundation
import Supabase

struct Profile: Codable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var inviteCode: String
    var reminderTime: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case inviteCode = "invite_code"
        case reminderTime = "reminder_time"
    }
}

struct ProfileRepository {
    private let columns = "id, display_name, invite_code, reminder_time"

    func myProfile() async throws -> Profile {
        let userId = try await Supa.client.auth.session.user.id
        return try await Supa.client
            .from("profiles")
            .select(columns)
            .eq("id", value: userId)
            .single()
            .execute()
            .value
    }

    func updateDisplayName(_ name: String) async throws {
        let userId = try await Supa.client.auth.session.user.id
        // returning: .minimal matters — the default (.representation) makes
        // PostgREST select * on the updated row, which trips over the revoked
        // phone_hash column and fails the whole update with 42501.
        try await Supa.client
            .from("profiles")
            .update(["display_name": name], returning: .minimal)
            .eq("id", value: userId)
            .execute()
    }
}
