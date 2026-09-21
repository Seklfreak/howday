import Foundation

/// The invite: the link handed out and the words that go with it.
///
/// The words are the feature. Howday has no usernames and no search, so an
/// invite that says only "get this app" ends with two people who both
/// installed it and still can't see each other — the recipient has to save
/// the sender's number for the link to go both ways. That sentence is why
/// the copy lives here, beside a test, rather than inline in a view.
enum Invite {
    /// `nil` when no `INVITE_URL` is configured, which hides every entry
    /// point rather than handing out a dead link.
    static var url: URL? { AppConfig.inviteURL }

    /// What lands in the recipient's chat, above the link itself.
    static let message = "How's your day, in one emoji? That's the whole app. "
        + "Add me to your contacts and we'll see each other's day."

    /// The sentence with the link inside it, which is what the share sheet
    /// is handed as its message.
    ///
    /// The link is repeated here rather than left to the shared URL alone:
    /// a share sheet gives each target its pick of the items, and Copy picks
    /// this text — verified, and what it put on the clipboard was an invite
    /// with no way to install the app. Targets that render the URL itself
    /// (Messages, Mail) still get it as a link, from the item.
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
