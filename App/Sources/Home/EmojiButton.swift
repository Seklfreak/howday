import SwiftUI

/// One mood in the picker and the collapsed mood bar: an emoji in a
/// translucent circle that rings and glows in its own mood colour when
/// selected. Sizes follow Dynamic Type through `TypeScale`.
struct EmojiButton: View {
    let emoji: String
    let isSelected: Bool
    var isWildcard = false
    /// Base sizes at the default text size; both follow Dynamic Type.
    let diameter: CGFloat
    let fontSize: CGFloat
    let action: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    /// Each button rings and glows in its own mood's color, not a shared
    /// accent — the ring wears the color it would turn.
    private var theme: MoodTheme { MoodTheme.forEmoji(emoji) }

    private var scaledDiameter: CGFloat { diameter * TypeScale.clamp(scale) }

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: fontSize * TypeScale.clamp(scale)))
                .frame(width: scaledDiameter, height: scaledDiameter)
                .background(Circle().fill(.white.opacity(isSelected ? 0.10 : 0.06)))
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(theme.accent, lineWidth: diameter > 60 ? 3 : 2.5)
                    } else {
                        // The daily wildcard keeps a dashed "surprise" ring.
                        Circle().strokeBorder(
                            .white.opacity(0.12),
                            style: StrokeStyle(lineWidth: 1.5, dash: isWildcard ? [6, 5] : [])
                        )
                    }
                }
                .shadow(color: isSelected ? theme.accent.opacity(0.55) : .clear, radius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(emoji) mood")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
