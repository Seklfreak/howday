import AppIntents
import SwiftUI
import WidgetKit

/// The Control Center tile (iOS 18): "Check in", which opens the app on
/// today's picker — or the board, if you already have. A control button
/// runs an intent; this one opens `howday://open?source=control-center`,
/// so the tap lands on the same screen the app icon would — and the app
/// can tell that this is where the person came from.
@available(iOS 18.0, *)
struct CheckInControl: ControlWidget {
    static let kind = "CheckInControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(WidgetSource.control.openURL ?? URL(string: "howday://open")!)) {
                Label("Check in", systemImage: "face.smiling")
            }
        }
        .displayName("Check in")
        .description("Open Howday to check in with today's mood.")
    }
}
