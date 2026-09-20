import Foundation

/// Where each friend's emoji sits in the widget. Deterministic for a given
/// day and widget size, so a timeline refresh never makes the sky jump;
/// a new day deals a new sky. Sizes follow recency: the newest check-in is
/// the biggest emoji, friends who have not checked in are small rings.
struct SkyLayout {
    struct Placement: Hashable {
        let friend: SkyFriend
        let center: CGPoint
        let diameter: CGFloat
    }

    let placements: [Placement]

    /// Emoji diameters by recency rank, in points, per widget width class.
    private static func ladder(for size: CGSize) -> [CGFloat] {
        if size.height >= 300 { return [66, 52, 46, 40, 36, 32, 28, 26] }
        if size.width > 250 { return [58, 46, 40, 34, 30, 26, 24] }
        return [46, 36, 30, 26, 24, 22]
    }

    private static func ringDiameter(for size: CGSize) -> CGFloat {
        size.height >= 300 ? 20 : (size.width > 250 ? 18 : 14)
    }

    /// Scattered, non-overlapping, newest biggest — the small and medium
    /// widgets. `inset` keeps the glow off the widget's edge; `topInset`
    /// and `bottomInset` leave room for a header or a caption.
    static func scattered(
        _ friends: [SkyFriend], in size: CGSize, day: String,
        inset: CGFloat = 8, topInset: CGFloat = 0, bottomInset: CGFloat = 0, labelAllowance: CGFloat = 0
    ) -> SkyLayout {
        var generator = SeededGenerator(seed: day + "\(Int(size.width))x\(Int(size.height))")
        let ladder = ladder(for: size)
        let ring = ringDiameter(for: size)
        var placed: [Placement] = []
        for (index, friend) in friends.enumerated() {
            let diameter = friend.isIn ? ladder[min(index, ladder.count - 1)] : ring
            let radius = diameter / 2
            let xRange = (inset + radius)...max(inset + radius, size.width - inset - radius)
            let yRange = (topInset + inset + radius)...max(topInset + inset + radius, size.height - bottomInset - inset - radius)
            var best = CGPoint(x: xRange.lowerBound, y: yRange.lowerBound)
            var bestClearance = -CGFloat.infinity
            for _ in 0..<48 {
                let candidate = CGPoint(
                    x: CGFloat.random(in: xRange, using: &generator),
                    y: CGFloat.random(in: yRange, using: &generator)
                )
                // A name under an emoji needs room too, so the required
                // gap grows by the label's height.
                let clearance = placed.map { other in
                    candidate.distance(to: other.center) - (radius + other.diameter / 2) - labelAllowance
                }.min() ?? .infinity
                if clearance > bestClearance {
                    bestClearance = clearance
                    best = candidate
                }
                if clearance >= 6 { break }
            }
            placed.append(Placement(friend: friend, center: best, diameter: diameter))
        }
        return SkyLayout(placements: placed)
    }

    /// The day's sky — the large widget: x is the time of the check-in from
    /// morning (left) to evening (right), y is dealt, sizes as above.
    static func byTime(
        _ friends: [SkyFriend], in size: CGSize, day: String,
        inset: CGFloat = 12, topInset: CGFloat, bottomInset: CGFloat, labelAllowance: CGFloat = 0
    ) -> SkyLayout {
        var generator = SeededGenerator(seed: day + "large")
        let ladder = ladder(for: size)
        let ring = ringDiameter(for: size)
        let calendar = Calendar.current
        var placed: [Placement] = []
        for (index, friend) in friends.enumerated() {
            let diameter = friend.isIn ? ladder[min(index, ladder.count - 1)] : ring
            let radius = diameter / 2
            let usableWidth = size.width - 2 * (inset + radius)
            let x: CGFloat
            if let at = friend.checkedInAt {
                let minutes = CGFloat(calendar.component(.hour, from: at) * 60 + calendar.component(.minute, from: at))
                // 6:00 → left edge, midnight → right edge; the night owls
                // and the early birds both stay on the sky.
                let fraction = min(max((minutes - 360) / (1440 - 360), 0), 1)
                x = inset + radius + fraction * usableWidth
            } else {
                x = inset + radius + CGFloat.random(in: 0...1, using: &generator) * usableWidth
            }
            let yRange = (topInset + radius)...max(topInset + radius, size.height - bottomInset - radius)
            var best = CGPoint(x: x, y: yRange.lowerBound)
            var bestClearance = -CGFloat.infinity
            for _ in 0..<40 {
                let candidate = CGPoint(x: x, y: CGFloat.random(in: yRange, using: &generator))
                let clearance = placed.map { other in
                    candidate.distance(to: other.center) - (radius + other.diameter / 2) - labelAllowance
                }.min() ?? .infinity
                if clearance > bestClearance {
                    bestClearance = clearance
                    best = candidate
                }
                if clearance >= 6 { break }
            }
            placed.append(Placement(friend: friend, center: best, diameter: diameter))
        }
        return SkyLayout(placements: placed)
    }
}

/// A tiny deterministic generator (SplitMix64) seeded from a string, so the
/// same day and size always deal the same sky. Swift's own generator is
/// seeded per process, which would reshuffle on every refresh.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}
