import Foundation
import Testing
@testable import Howday

/// The widget's emoji placement: deterministic per day and size, newest
/// biggest, nothing overlapping, and the large widget's x is the time.
struct SkyLayoutTests {
    /// Fixed ids: the drift is seeded by the friend's id, and a per-process
    /// hash would make the sky differ from one test run to the next.
    private func friend(_ index: Int, _ name: String, emoji: String?, hour: Int?) -> SkyFriend {
        SkyFriend(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", index))") ?? UUID(),
            name: name, emoji: emoji,
            checkedInAt: hour.map { Calendar.current.date(bySettingHour: $0, minute: 0, second: 0, of: .now)! }
        )
    }

    private var friends: [SkyFriend] {
        [
            friend(1, "Chloé", emoji: "😢", hour: 18), friend(2, "Jonas", emoji: "😕", hour: 14),
            friend(3, "Ben", emoji: "😐", hour: 11), friend(4, "Sam", emoji: "🙂", hour: 10),
            friend(5, "Anna", emoji: "😄", hour: 9), friend(6, "Dev", emoji: nil, hour: nil),
        ]
    }

    private let small = CGSize(width: 170, height: 170)
    private let large = CGSize(width: 364, height: 300)

    @Test func sameDayAndSizeDealTheSameSky() {
        let first = SkyLayout.scattered(friends, in: small, day: "2026-09-19")
        let again = SkyLayout.scattered(friends, in: small, day: "2026-09-19")
        #expect(first.placements == again.placements)
    }

    @Test func aNewDayDealsANewSky() {
        let today = SkyLayout.scattered(friends, in: small, day: "2026-09-19")
        let tomorrow = SkyLayout.scattered(friends, in: small, day: "2026-09-20")
        #expect(today.placements.map(\.center) != tomorrow.placements.map(\.center))
    }

    @Test func newestIsBiggestAndMissingFriendsAreRings() {
        let layout = SkyLayout.scattered(friends, in: small, day: "2026-09-19")
        let diameters = layout.placements.map(\.diameter)
        #expect(diameters.first == diameters.max())
        #expect(layout.placements.last?.friend.name == "Dev")
        #expect(layout.placements.last!.diameter < layout.placements[4].diameter)
    }

    @Test func everythingStaysInsideTheWidget() {
        for size in [small, CGSize(width: 364, height: 170), large] {
            let layout = SkyLayout.scattered(friends, in: size, day: "2026-09-19", inset: 10)
            for placement in layout.placements {
                let r = placement.diameter / 2
                #expect(placement.center.x - r >= 0 && placement.center.x + r <= size.width, "\(placement.friend.name)")
                #expect(placement.center.y - r >= 0 && placement.center.y + r <= size.height, "\(placement.friend.name)")
            }
        }
    }

    /// Across a run of drift steps, not just the dealt positions: the
    /// placement has to leave room for two neighbours to drift toward
    /// each other.
    @Test func emojiDoNotOverlapWhereThereIsRoom() {
        for phase in stride(from: 0, to: 60, by: 7) {
            let layout = SkyLayout.scattered(friends, in: large, day: "2026-09-19", phase: phase)
            for (index, one) in layout.placements.enumerated() {
                for other in layout.placements.dropFirst(index + 1) {
                    let dx = one.center.x - other.center.x
                    let dy = one.center.y - other.center.y
                    let distance = (dx * dx + dy * dy).squareRoot()
                    #expect(
                        distance >= (one.diameter + other.diameter) / 2,
                        "\(one.friend.name) vs \(other.friend.name) at phase \(phase)"
                    )
                }
            }
        }
    }

    @Test func theLargeWidgetOrdersTheDayLeftToRight() {
        let layout = SkyLayout.byTime(friends, in: large, day: "2026-09-19", topInset: 0, bottomInset: 0)
        let byName = Dictionary(uniqueKeysWithValues: layout.placements.map { ($0.friend.name, $0.center.x) })
        #expect(byName["Anna"]! < byName["Sam"]!)
        #expect(byName["Sam"]! < byName["Ben"]!)
        #expect(byName["Ben"]! < byName["Jonas"]!)
        #expect(byName["Jonas"]! < byName["Chloé"]!)
    }

    @Test func driftMovesEachStepALittleAndStaysInside() {
        let before = SkyLayout.scattered(friends, in: small, day: "2026-09-19", phase: 100, inset: 10)
        let after = SkyLayout.scattered(friends, in: small, day: "2026-09-19", phase: 101, inset: 10)
        var moved = false
        for (one, next) in zip(before.placements, after.placements) {
            let dx = abs(one.center.x - next.center.x)
            let dy = abs(one.center.y - next.center.y)
            #expect(dx <= 2 * SkyLayout.driftAmplitude && dy <= 2 * SkyLayout.driftAmplitude, "\(one.friend.name)")
            if dx + dy > 0.5 { moved = true }
            let r = next.diameter / 2
            #expect(next.center.x - r >= 0 && next.center.x + r <= small.width, "\(next.friend.name)")
            #expect(next.center.y - r >= 0 && next.center.y + r <= small.height, "\(next.friend.name)")
        }
        #expect(moved)
    }

    @Test func phaseIsAFiveMinuteStep() {
        // 999,900 is a whole number of five-minute steps since the epoch.
        let date = Date(timeIntervalSince1970: 999_900)
        #expect(SkyLayout.phase(at: date.addingTimeInterval(299)) == SkyLayout.phase(at: date))
        #expect(SkyLayout.phase(at: date.addingTimeInterval(300)) == SkyLayout.phase(at: date) + 1)
    }

    @Test func seededGeneratorIsStable() {
        var one = SeededGenerator(seed: "2026-09-19")
        var two = SeededGenerator(seed: "2026-09-19")
        #expect(one.next() == two.next())
        var other = SeededGenerator(seed: "2026-09-20")
        #expect(one.next() != other.next())
    }
}
