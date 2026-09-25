import Foundation

/// What a widget timeline entry carries. Friends are sorted the way the
/// layout wants them: checked in first, most recent first, then the rest
/// by name.
struct SkySnapshot: Hashable, Sendable, Codable {
    enum State: String, Hashable, Sendable, Codable {
        case signedOut
        case failed
        case ready
    }

    let state: State
    /// The local day the snapshot describes, `LocalDay` form.
    let day: String
    /// Your own emoji today — nil is the gate: friends' moods stay hidden.
    let mine: String?
    var friends: [SkyFriend]
    /// The day's wildcard for the lock-screen picker; nil when there is
    /// no user to derive it from.
    var wildcard: String?
    /// When the board was read. Shown on the large widget so a stale sky
    /// can be told from a quiet day.
    var fetchedAt: Date = .now
    /// True when this is the last good read rather than a fresh one. The
    /// sky is still true, just older — but the timeline should come back
    /// sooner than it would after a clean refresh.
    var isStale = false

    var friendsIn: Int { friends.filter(\.isIn).count }

    /// How long a stored snapshot stands in for a fetch. The app publishes
    /// the board it has just read, so a reload that follows one arrives to
    /// a sky seconds old and need not make the round trip itself.
    static let freshFor: TimeInterval = 90

    /// Whether this snapshot can be served instead of reading the board.
    /// Stale is excluded on purpose: that flag is how the app and the push
    /// extension say "something changed that I have not read yet".
    var isFresh: Bool {
        state == .ready && !isStale && day == LocalDay.string()
            && fetchedAt.timeIntervalSinceNow > -Self.freshFor
    }

    /// Whether a viewer would see the same thing. `fetchedAt` is
    /// deliberately not part of it — a fresh read of an unchanged board is
    /// exactly the case that must not spend a reload.
    func showsSameAs(_ other: SkySnapshot?) -> Bool {
        guard let other else { return false }
        return state == other.state && day == other.day && mine == other.mine
            && friends == other.friends && wildcard == other.wildcard
    }

    /// What the lock-screen picker offers: the suggestions and the
    /// wildcard, as the app's own picker does.
    var choices: [String] { MoodEmoji.suggestions + (wildcard.map { [$0] } ?? []) }

    /// The lock-screen strip fits six in a row, not all of `choices`: six
    /// of them in a shuffled order, drawn for the day so a timeline refresh doesn't reshuffle
    /// the row under someone's thumb. The wildcard is the per-user half of
    /// the seed, so friends don't all get the same six.
    var lockScreenChoices: [String] {
        MoodEmoji.pick(6, from: choices, seed: "\(day)|\(wildcard ?? "")")
    }

    static let signedOut = SkySnapshot(state: .signedOut, day: LocalDay.string(), mine: nil, friends: [])
    static let failed = SkySnapshot(state: .failed, day: LocalDay.string(), mine: nil, friends: [])

    /// What the gallery and a redacted widget show: a full sky.
    static var placeholder: SkySnapshot {
        // Clock times rather than "minutes ago": the large widget lays the
        // day out left to right, and a sample that all happened just now
        // would stack in the evening column.
        let calendar = Calendar.current
        func sample(_ index: Int, _ name: String, _ emoji: String?, at hour: Int, _ minute: Int) -> SkyFriend {
            SkyFriend(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)") ?? UUID(),
                name: name, emoji: emoji,
                checkedInAt: emoji == nil ? nil : calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now)
            )
        }
        let friends = [
            sample(1, "Anna", "😄", at: 9, 12), sample(2, "Sam", "🙂", at: 10, 5),
            sample(3, "Ben", "😐", at: 11, 40), sample(4, "Jonas", "😕", at: 14, 20),
            sample(5, "Chloé", "😢", at: 17, 48), sample(6, "Dev", nil, at: 0, 0),
            sample(7, "Mira", nil, at: 0, 0),
        ]
        return SkySnapshot(state: .ready, day: LocalDay.string(), mine: "🙂", friends: SkySnapshot.sorted(friends), wildcard: "🚀")
    }

    /// What a friend's mood did to this sky.
    enum Patch: Equatable {
        /// It changed, and the widgets should be told.
        case written(SkySnapshot)
        /// This sky already showed it — the app read the board just before
        /// the push landed, say. Nothing to draw, and a reload spent on
        /// nothing is one the next friend's push does not get.
        case alreadyShown
        /// This sky cannot answer for that friend: a different day, a read
        /// that failed, someone who is not on it. The caller falls back to
        /// saying the sky is behind the truth.
        case cannotAnswer
    }

    /// This sky with one friend's mood written into it.
    ///
    /// The push carries the mood, so a friend's check-in reaches the widget
    /// without anyone reading the board: the alternative was to mark the
    /// stored sky stale and let each widget fetch, and a widget's fetch runs
    /// on a locked phone with the radio asleep, which is the slow part and
    /// the part that fails. `fetchedAt` moves to now deliberately — this is
    /// the freshest the sky has been, and leaving it behind would send the
    /// widget to the network for the one thing it has just been told.
    func applying(emoji: String, from friend: UUID, at when: Date = .now) -> Patch {
        guard state == .ready, day == LocalDay.string(),
              let index = friends.firstIndex(where: { $0.id == friend }) else { return .cannotAnswer }
        guard friends[index].emoji != emoji else { return .alreadyShown }
        var patched = friends
        patched[index] = SkyFriend(
            id: friends[index].id, name: friends[index].name, emoji: emoji, checkedInAt: when
        )
        var copy = self
        copy.friends = Self.sorted(patched)
        copy.fetchedAt = when
        copy.isStale = false
        return .written(copy)
    }

    static func sorted(_ friends: [SkyFriend]) -> [SkyFriend] {
        friends.sorted { lhs, rhs in
            switch (lhs.checkedInAt, rhs.checkedInAt) {
            case let (left?, right?): return left > right
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.name < rhs.name
            }
        }
    }
}

/// The last sky that loaded, kept in the App Group so a failed refresh has
/// something true to fall back on.
enum SkySnapshotStore {
    private static let key = "widget.lastSnapshot"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: NameMap.appGroup) ?? .standard
    }

    static func save(_ snapshot: SkySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> SkySnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SkySnapshot.self, from: data)
    }

    /// Mark what is stored as behind the truth, so the next refresh reads
    /// the board instead of serving this. It stays as the fallback if that
    /// read fails — older than the truth still beats an error.
    static func invalidate() {
        guard var snapshot = load() else { return }
        snapshot.isStale = true
        save(snapshot)
    }

    /// Writes a friend's new mood straight into the stored sky, so a widget
    /// can draw it without reading the board.
    static func applyCheckin(by friend: UUID, emoji: String, at when: Date = .now) -> SkySnapshot.Patch {
        guard let stored = load() else { return .cannotAnswer }
        let patch = stored.applying(emoji: emoji, from: friend, at: when)
        if case .written(let updated) = patch { save(updated) }
        return patch
    }

    /// Sign-out takes the sky with it, or the widget keeps drawing a
    /// friend's mood for whoever picks the phone up next.
    static func clear() { defaults.removeObject(forKey: key) }
}
