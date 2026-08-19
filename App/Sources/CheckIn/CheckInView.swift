import SwiftUI

// M1: the real check-in flow (mood picker, emoji, note, upsert to checkins).
struct CheckInView: View {
    var body: some View {
        ContentUnavailableView(
            "Check-in coming in M1",
            systemImage: "face.smiling",
            description: Text("Daily mood picker lands here.")
        )
    }
}
