import SwiftUI

// M1: month calendar of your own moods.
struct HistoryView: View {
    var body: some View {
        ContentUnavailableView(
            "History coming in M1",
            systemImage: "calendar",
            description: Text("Your mood calendar lands here.")
        )
    }
}
