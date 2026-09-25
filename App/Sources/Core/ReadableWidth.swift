import SwiftUI

extension View {
    /// Caps a single-column screen at the widest iPhone and centres it.
    /// On a phone this changes nothing; on the iPhone Duo's inner display
    /// (951pt across when open) a form stretched edge to edge, with fields
    /// and buttons several times wider than anything they hold.
    func readableWidth() -> some View {
        frame(maxWidth: 440).frame(maxWidth: .infinity)
    }
}
