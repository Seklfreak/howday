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

    private static let steps = [
        "You each have the other's number saved. Both directions, or neither of you appears.",
        "They install Howday and sign in with that number.",
        "Their emoji lands on your board, and yours on theirs.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Scrolls rather than squeezes: three sentences of steps plus
            // two buttons do not fit the medium detent at the accessibility
            // sizes, and the buttons are the part that must stay put.
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            VStack(spacing: 12) {
                if let url = Invite.url {
                    // The URL is the item, so the sheet is link-shaped and
                    // Messages unfurls a preview; the message carries the
                    // link too, for the targets that take only the text.
                    ShareLink(
                        item: url,
                        subject: Text("Howday"),
                        message: Text(Invite.shareText(url: url)),
                        // Without it the sheet heads the invite with Safari's
                        // compass and the bare host, because a URL nobody has
                        // fetched yet has no metadata to draw on.
                        preview: SharePreview("Howday", image: Image(.shareIcon))
                    ) {
                        Text("Invite a friend").frame(maxWidth: .infinity)
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
            .padding(24)
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        .onAppear { Analytics.screen(.invite) }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 28 * TypeScale.clamp(scale), height: 28 * TypeScale.clamp(scale))
                .background(Circle().fill(.tint.opacity(0.16)))
                .overlay { Circle().strokeBorder(.tint.opacity(0.45)) }
                // The number is ordering, not content — VoiceOver reads the
                // step itself, in order, without "1" in front of it.
                .accessibilityHidden(true)
            Text(text).font(.subheadline)
        }
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
