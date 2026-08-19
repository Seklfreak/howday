import SwiftUI

// M3: today board — friends' moods, gated on your own check-in, realtime.
struct BoardView: View {
    var body: some View {
        ContentUnavailableView(
            "Board coming in M3",
            systemImage: "person.2",
            description: Text("Your friends' moods for today land here.")
        )
    }
}
