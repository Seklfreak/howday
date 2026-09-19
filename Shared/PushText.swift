/// The named versions of the server's generic push texts (push-checkin,
/// push-joined), with the sender's first name in place of "a friend". The
/// mood itself is deliberately not in the payload: seeing it is what
/// checking in earns.
enum PushText {
    static func body(name: String, kind: String?) -> String {
        switch kind {
        case "update": "\(name)'s mood changed 💫"
        case "join": "\(name) joined Howday 👋"
        default: "\(name) just checked in 💫"
        }
    }
}
