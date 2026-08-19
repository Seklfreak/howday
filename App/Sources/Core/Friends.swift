import Foundation
import Supabase

struct FriendProfile: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

/// A friendships row with both profiles embedded via their foreign keys.
struct FriendshipRow: Codable, Identifiable, Sendable {
    let id: UUID
    let status: String
    let requester: FriendProfile
    let addressee: FriendProfile
}

/// The friendships table split into what the UI actually renders,
/// from the perspective of the signed-in user.
struct FriendsState: Sendable {
    var friends: [(friendshipId: UUID, profile: FriendProfile)] = []
    var incoming: [(friendshipId: UUID, profile: FriendProfile)] = []
    var outgoing: [(friendshipId: UUID, profile: FriendProfile)] = []

    /// Profile ids with any existing relationship, for button states.
    var relatedProfileIds: Set<UUID> {
        Set((friends + incoming + outgoing).map(\.profile.id))
    }
}

struct FriendsRepository {
    private static let columns = """
    id, status, \
    requester:profiles!friendships_requester_fkey(id, display_name), \
    addressee:profiles!friendships_addressee_fkey(id, display_name)
    """

    func state() async throws -> FriendsState {
        let myId = try await Supa.client.auth.session.user.id
        let rows: [FriendshipRow] = try await Supa.client
            .from("friendships")
            .select(Self.columns)
            .execute()
            .value
        var result = FriendsState()
        for row in rows {
            let other = row.requester.id == myId ? row.addressee : row.requester
            switch (row.status, row.requester.id == myId) {
            case ("accepted", _): result.friends.append((row.id, other))
            case ("pending", true): result.outgoing.append((row.id, other))
            case ("pending", false): result.incoming.append((row.id, other))
            default: break
            }
        }
        result.friends.sort { $0.profile.displayName < $1.profile.displayName }
        return result
    }

    func sendRequest(to profileId: UUID) async throws {
        struct Payload: Encodable {
            let requester: UUID
            let addressee: UUID
            let status: String
        }
        let myId = try await Supa.client.auth.session.user.id
        try await Supa.client
            .from("friendships")
            .insert(Payload(requester: myId, addressee: profileId, status: "pending"), returning: .minimal)
            .execute()
    }

    func accept(friendshipId: UUID) async throws {
        try await Supa.client
            .from("friendships")
            .update(["status": "accepted"], returning: .minimal)
            .eq("id", value: friendshipId)
            .execute()
    }

    /// Decline, cancel, or unfriend — all the same delete.
    func remove(friendshipId: UUID) async throws {
        try await Supa.client
            .from("friendships")
            .delete(returning: .minimal)
            .eq("id", value: friendshipId)
            .execute()
    }

    /// Redeems a friend's invite code; returns the new friend's name.
    func redeemInvite(code: String) async throws -> String? {
        struct Row: Decodable {
            let friendName: String
            enum CodingKeys: String, CodingKey { case friendName = "friend_name" }
        }
        let rows: [Row] = try await Supa.client
            .rpc("redeem_invite", params: ["code": code])
            .execute()
            .value
        return rows.first?.friendName
    }
}
