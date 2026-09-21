import SwiftUI

/// The sheet behind every "Invite a friend": what the recipient actually has
/// to do, and then the system share sheet.
///
/// The explainer is not a welcome mat. The mutual-contacts rule is the one
/// thing about Howday nobody guesses, and it is the sender — not the
/// recipient — who has to act on it, so it has to be said on this side of
/// the share sheet as well as inside the message.
struct InviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1
    /// Two lines of a step, so every row is the same height whether its
    /// sentence wraps or not. Scales with the text, because at the larger
    /// sizes two lines is taller.
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 44
    /// What the content actually measures, which is what the sheet is then
    /// sized to. A fixed detent left a hand's width of nothing between the
    /// last step and the buttons.
    @State private var contentHeight: CGFloat = 0

    private static let steps = [
        "You each have the other's number saved. Both directions, or neither of you appears.",
        "They install Howday and sign in with that number.",
        "Their emoji lands on your board, and yours on theirs.",
    ]

    var body: some View {
        // One column, buttons included, rather than a scroll view with the
        // buttons pinned under it: pinned, the slack between the shortest
        // content and the detent all collected above them.
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How a friend shows up")
                        .font(.title2.weight(.bold))
                    Text("There are no usernames to search. Your address book is the whole thing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, text in
                        step(index + 1, text)
                    }
                }
                buttons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeight.self, value: proxy.size.height)
                }
            }
        }
        // Nothing to scroll at the fitted height, and a sheet that rubber-bands
        // when it is already showing everything reads as broken.
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(ContentHeight.self) { contentHeight = $0 }
        .presentationDragIndicator(.visible)
        // `.large` stays available for the accessibility sizes, where the
        // measured height is clamped to the screen and the scroll view is
        // what carries the rest.
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight), .large] : [.medium, .large])
        .onAppear { Analytics.screen(.invite) }
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 12) {
            if let url = Invite.url {
                // One item carrying both readings, and no `message:` — see
                // InviteItem for why that pairing is what duplicated the
                // link in Messages.
                ShareLink(
                    item: InviteItem(url: url),
                    subject: Text("Howday"),
                    // Without it the sheet heads the invite with Safari's
                    // compass and the bare host, because a URL nobody has
                    // fetched yet has no metadata to draw on.
                    preview: SharePreview("Howday", image: Image(.shareIcon))
                ) {
                    Text("Invite a friend").frame(maxWidth: .infinity).onAccent()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                // ShareLink reports no outcome — iOS doesn't tell the app
                // whether anything was sent — so the tap is what's counted.
                .simultaneousGesture(TapGesture().onEnded { Analytics.track("invite_shared") })
            }
            Button { dismiss() } label: {
                Text("Not now").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(Color.primary)
        }
        .padding(.top, 2)
    }

    /// A numbered step: the number centred on its sentence, in a row at
    /// least two lines tall.
    ///
    /// Both halves earn their place. The steps run two lines, one, and two,
    /// so without the even row height the numbers land 55pt apart and then
    /// 43pt, and the column reads as crooked. Centring is what keeps each
    /// number with its own sentence inside that fixed row — aligned to the
    /// first line instead, the spare height of the one-line step opened a
    /// gap under it that looked like a missing fourth step.
    private func step(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 28 * TypeScale.clamp(scale), height: 28 * TypeScale.clamp(scale))
                .background(Circle().fill(.tint.opacity(0.16)))
                .overlay { Circle().strokeBorder(.tint.opacity(0.45)) }
                // The number is ordering, not content — VoiceOver reads the
                // step itself, in order, without "1" in front of it.
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A floor, not a cap: a step that runs to four lines at the
        // accessibility sizes still gets them.
        .frame(minHeight: rowHeight)
    }
}

/// The measured height of the sheet's content, read back to size the sheet.
private struct ContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The board's own way in, under the grid: the one entry point that stays
/// visible once the board has people on it, because that is when a user
/// stops looking for a way to add more.
struct InviteTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: "person.badge.plus")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite a friend")
                        .font(.subheadline.weight(.semibold))
                    Text("The board only fills up if they're here too")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.tint.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
        .buttonStyle(.plain)
    }
}
