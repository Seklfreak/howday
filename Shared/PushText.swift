/// The named versions of the server's generic push texts (push-checkin,
/// push-joined), with the sender's first name in place of "a friend".
///
/// **No mood in any of these**, and the 💫 is a fixed sparkle rather than
/// the sender's emoji. Seeing a friend's mood is what checking in earns —
/// the board and both widgets gate on your own check-in — and a banner
/// carrying the emoji would walk straight around that gate. The payload
/// *does* hold the mood now (the notification extension writes it into the
/// sky the widgets read; see CLAUDE.md, "Push notifications"), so keeping
/// it out of the text here is the only thing still enforcing the rule.
enum PushText {
    static func body(name: String, kind: String?) -> String {
        switch kind {
        case "update": "\(name)'s emoji changed 💫"
        case "join": "\(name) joined Howday 👋"
        default: "\(name) just checked in 💫"
        }
    }
}
