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
    let friends: [SkyFriend]
    /// The day's sixth offer for the lock-screen picker; nil when there is
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

    /// What the lock-screen picker offers: the five suggestions and the
    /// wildcard, as the app's own picker does.
    var choices: [String] { MoodEmoji.suggestions + (wildcard.map { [$0] } ?? []) }

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
}
