import Foundation
import Supabase
import WidgetKit

/// Keeps the widgets in step with what the app has just read.
///
/// Every reload request draws on the same daily refresh budget iOS gives a
/// widget, and the requests carrying nothing new are what push the ones
/// that matter past it — a friend's push landing on a spent budget is a
/// widget that simply does not refresh. The board used to ask for a reload
/// on *every* read: each appear, each pull, each realtime event, identical
/// board or not. So the app now publishes what it read into the App Group
/// and asks for a reload only when the sky a viewer would see has changed.
enum WidgetSync {
    /// The board as the widget would draw it. Always stored — that is what
    /// lets the widget skip its own round trip — but only reloaded when it
    /// differs from what the widget is already showing.
    static func publish(_ board: BoardState) {
        // currentSession, not session: this needs only the id, and the
        // refreshing one throws without a network.
        guard let myId = Supa.client.auth.currentSession?.user.id else { return }
        let day = LocalDay.string()
        let friends = board.entries.map {
            SkyFriend(
                id: $0.id, name: $0.identity.name,
                emoji: $0.checkin?.emoji, checkedInAt: $0.checkin?.checkedInAt
            )
        }
        let snapshot = SkySnapshot(
            state: .ready, day: day, mine: board.mine?.emoji,
            friends: SkySnapshot.sorted(friends),
            wildcard: MoodEmoji.wildcard(for: myId, day: day)
        )
        let changed = !snapshot.showsSameAs(SkySnapshotStore.load())
        SkySnapshotStore.save(snapshot)
        guard changed else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Something changed that the app has not read back — your own
    /// check-in, a drained queue. What is stored is now behind the truth,
    /// so it is marked as such (the widget won't serve it in place of a
    /// read) before the reload.
    static func invalidate() {
        SkySnapshotStore.invalidate()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Nobody is signed in. The stored sky goes with the session, or the
    /// widget keeps drawing a friend's mood on a signed-out phone.
    static func signedOut() {
        SkySnapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
