import Foundation

/// One friend on the widget: the name from the address book (via the name
/// map the app writes), today's emoji if they have checked in, and when.
struct SkyFriend: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let emoji: String?
    let checkedInAt: Date?

    var isIn: Bool { emoji != nil }
}
