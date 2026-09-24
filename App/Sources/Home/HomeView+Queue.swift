import SwiftUI

/// The home screen's half of the check-in queue: adopting a check-in made
/// elsewhere (the lock-screen widget) and retrying one parked by a dead
/// network. An extension rather than more of the view — this is about the
/// queue, not about what is on screen.
extension HomeView {
    /// The day changed under a mounted screen: forget yesterday and load
    /// today from scratch, the way a cold launch would. Waits for a save
    /// still in flight first — it targets the day it was tapped on, and
    /// its outcome must not land on the new day's selection.
    func startNewDay() async {
        guard loadedDay != LocalDay.string() else { return }
        await saveTask?.value
        isLoading = true
        selected = nil
        confirmed = nil
        notice = nil
        errorMessage = nil
        isChangingMood = false
        await load()
    }

    /// Picks up a check-in the server has that this screen doesn't — made
    /// from the lock-screen widget while the app was backgrounded. Runs on
    /// the save chain so it can't race a tap made just now, and only ever
    /// moves the selection to what the server holds, never away from a
    /// save still in flight.
    func adoptServerCheckin() async {
        let previous = saveTask
        let task = Task {
            await previous?.value
            guard let row = try? await CheckinRepository().today()?.emoji, row != confirmed else { return }
            confirmed = row
            if selected != row { withAnimation { selected = row } }
            ReminderScheduler.cancelToday()
            Analytics.screen(.board)
        }
        saveTask = task
        await task.value
    }

    /// Retries the parked check-in, if any, on the save chain so it can't
    /// race a fresh tap, and reflects the outcome on screen.
    @discardableResult
    func flushPending() async -> CheckinQueue.Outcome {
        guard CheckinQueue.pending != nil else { return .nothing }
        let previous = saveTask
        let task = Task<CheckinQueue.Outcome, Never> {
            await previous?.value
            let outcome = await CheckinQueue.drain()
            switch outcome {
            case .nothing:
                break
            case .saved(let entry):
                confirmed = entry.emoji
                notice = nil
                ReminderScheduler.cancelToday()
                WidgetSync.invalidate()
                // Same events as a direct save: the funnel counts the
                // check-in once, when it actually reaches the server.
                Analytics.track(
                    entry.isEdit ? "checkin_edited" : "checkin_saved",
                    ["source": WidgetSource.app.rawValue]
                )
            case .stillPending:
                notice = "Saving when you're back online."
            case .expired:
                // Not saved as yesterday: saveToday cannot backdate, and a
                // parked entry must not become the way around that.
                notice = "Yesterday's emoji didn't reach the server before midnight."
                Analytics.track("checkin_expired")
            case .rejected(let entry, let message):
                if selected == entry.emoji { withAnimation { selected = confirmed } }
                notice = nil
                errorMessage = message
            }
            return outcome
        }
        saveTask = Task { _ = await task.value }
        return await task.value
    }
}
