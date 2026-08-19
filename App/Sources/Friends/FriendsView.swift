import SwiftUI

// M2: contacts matching, invite links, requests in/out, unfriend.
struct FriendsView: View {
    var body: some View {
        ContentUnavailableView(
            "Friends coming in M2",
            systemImage: "person.badge.plus",
            description: Text("Contact matching and invites land here.")
        )
    }
}
