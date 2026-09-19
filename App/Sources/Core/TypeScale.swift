import SwiftUI

/// Dynamic Type for the things that aren't text: emoji glyphs, ring
/// diameters, avatar frames, calendar cells. Text styles follow the user's
/// size on their own; these are pinned in points and would otherwise ignore
/// it, leaving a 53pt body label next to a 56pt avatar.
///
/// Used through `@ScaledMetric(relativeTo: .largeTitle) var scale: CGFloat = 1`
/// and `TypeScale.clamp(scale)`: `.largeTitle` is the style that grows the
/// least across the accessibility sizes (×1.8 at the top, against ×3 for
/// body), and the clamp stops even that — a 100pt mood circle at ×1.8 no
/// longer fits two across on a 375pt screen, and the picker has to stay a
/// grid of tappable moods, not a scrolling list of one.
enum TypeScale {
    /// The most any pinned metric grows. Chosen so the home picker still
    /// fits two columns of 100pt circles on the narrowest supported iPhone.
    static let maximum: CGFloat = 1.5

    static func clamp(_ scale: CGFloat) -> CGFloat {
        min(scale, maximum)
    }
}
