import AppIntents
import SwiftUI
import WidgetKit

/// The Control Center tile (iOS 18): "Check in", which opens the app on
/// today's picker — or the board, if you already have. A control button
/// runs an intent; this one does nothing itself and only asks to open the
/// app, so the tap lands on the same screen the app icon would, without
/// hunting for it.
@available(iOS 18.0, *)
struct CheckInControl: ControlWidget {
    static let kind = "CheckInControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenHowdayIntent()) {
                Label("Check in", systemImage: "face.smiling")
            }
        }
        .displayName("Check in")
        .description("Open Howday to check in with today's mood.")
    }
}

/// Opens the app, nothing more. `openAppWhenRun` is what makes a control
/// or a Siri request bring the app to the front.
@available(iOS 18.0, *)
struct OpenHowdayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Howday"
    static let description = IntentDescription("Opens Howday to check in with today's mood.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
