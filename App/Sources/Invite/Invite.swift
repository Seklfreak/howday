import CoreTransferable
import Foundation

/// The invite: the link handed out and the words that go with it.
///
/// The words are the feature, which is why they live here beside a test
/// rather than inline in a view. They are also all the recipient gets: the
/// mutual-contacts rule is explained to the *sender*, in `InviteSheet`,
/// because the sender is the one who can act on it. An invite that opens by
/// instructing a stranger to save your number reads like a chore.
enum Invite {
    /// `nil` when no `INVITE_URL` is configured, which hides every entry
    /// point rather than handing out a dead link.
    static var url: URL? { AppConfig.inviteURL }

    /// What lands in the recipient's chat, reading into the link itself.
    static let message = "How's your day, in one emoji? That's the whole app. Here it is:"

    /// The sentence with the link on the end of it — the whole invite as one
    /// piece of text.
    static func shareText(url: URL) -> String {
        "\(message) \(url.absoluteString)"
    }

    /// Settings' quiet answer to "is anyone here yet?".
    static func contactsSummary(count: Int) -> String {
        switch count {
        case 0: "None of your contacts are on Howday yet"
        case 1: "1 of your contacts is on Howday"
        default: "\(count) of your contacts are on Howday"
        }
    }
}

/// What the share sheet is handed: the invite as words for the targets that
/// take text, and as a link for the ones that take URLs.
///
/// One item, deliberately. `ShareLink`'s own `message:` is a *second* item,
/// and the sheet lets every target pick from the pile — which went wrong in
/// both directions. With the link in the message as well as the item,
/// Messages took both and put it in the bubble twice; with the link only in
/// the item, Copy took the message and left the clipboard holding an invite
/// with no way to install the app. Two representations of one item cannot
/// do either: whatever a target picks, it gets the sentence and the link,
/// once.
struct InviteItem: Transferable {
    let url: URL

    var text: String { Invite.shareText(url: url) }

    static var transferRepresentation: some TransferRepresentation {
        // Text first, so it is what a target takes unless it specifically
        // wants a URL: the sentence is the half that makes the invite work,
        // and a bare link loses it.
        ProxyRepresentation(exporting: \.text)
        ProxyRepresentation(exporting: \.url)
    }
}
