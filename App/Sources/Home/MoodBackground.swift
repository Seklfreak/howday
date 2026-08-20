import SwiftUI

/// The liquid-crystal backdrop: soft blooms over a deep base, tinted by the
/// current mood and drifting slowly like the crystal in a warming ring. Mood
/// changes cross-fade; the drift pauses under Reduce Motion.
struct MoodBackground: View {
    let theme: MoodTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            theme.deep
            bloom(theme.glow.opacity(0.55), center: .init(x: 0.18, y: 0.08), radius: 0.75)
                .offset(x: drift ? 14 : -14, y: drift ? 10 : -10)
            bloom(theme.accent.opacity(0.28), center: .init(x: 0.88, y: 0.30), radius: 0.65)
                .offset(x: drift ? -12 : 12, y: drift ? 6 : -6)
            bloom(theme.glow.opacity(0.40), center: .init(x: 0.50, y: 1.05), radius: 0.80)
                .offset(y: drift ? -14 : 14)
        }
        // Oversize so the drifting blooms never reveal an edge.
        .scaleEffect(1.25)
        .animation(.easeInOut(duration: 0.9), value: theme)
        .ignoresSafeArea()
        .onAppear {
            // withAnimation, NOT an .animation modifier: a repeatForever
            // animation attached to the view also captures its initial
            // layout, leaving the whole backdrop mid-flight for 14s.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
        .accessibilityHidden(true)
    }

    private func bloom(_ color: Color, center: UnitPoint, radius: Double) -> some View {
        Rectangle()
            .fill(EllipticalGradient(
                colors: [color, .clear],
                center: center,
                startRadiusFraction: 0,
                endRadiusFraction: radius
            ))
    }
}
