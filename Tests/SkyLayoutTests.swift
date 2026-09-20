import Foundation
import Testing
@testable import Howday

/// The widget's emoji placement: deterministic per day and size, newest
/// biggest, nothing overlapping, and the large widget's x is the time.
struct SkyLayoutTests {
    private func friend(_ name: String, emoji: String?, hour: Int?) -> SkyFriend {
        SkyFriend(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", abs(name.hashValue % 90) + 10))") ?? UUID(),
            name: name, emoji: emoji,
            checkedInAt: hour.map { Calendar.current.date(bySettingHour: $0, minute: 0, second: 0, of: .now)! }
        )
    }

    private var friends: [SkyFriend] {
        [
            friend("Chloé", emoji: "😢", hour: 18), friend("Jonas", emoji: "😕", hour: 14),
            friend("Ben", emoji: "😐", hour: 11), friend("Sam", emoji: "🙂", hour: 10),
            friend("Anna", emoji: "😄", hour: 9), friend("Dev", emoji: nil, hour: nil),
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

    @Test func emojiDoNotOverlapWhereThereIsRoom() {
        let layout = SkyLayout.scattered(friends, in: large, day: "2026-09-19")
        for (index, one) in layout.placements.enumerated() {
            for other in layout.placements.dropFirst(index + 1) {
                let dx = one.center.x - other.center.x
                let dy = one.center.y - other.center.y
                let distance = (dx * dx + dy * dy).squareRoot()
                #expect(distance >= (one.diameter + other.diameter) / 2, "\(one.friend.name) vs \(other.friend.name)")
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

    @Test func seededGeneratorIsStable() {
        var one = SeededGenerator(seed: "2026-09-19")
        var two = SeededGenerator(seed: "2026-09-19")
        #expect(one.next() == two.next())
        var other = SeededGenerator(seed: "2026-09-20")
        #expect(one.next() != other.next())
    }
}
