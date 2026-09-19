import Foundation

/// The hash → first-name map the app hands its notification extension
/// through the App Group container. The server never knows a name: a push
/// carries the sender's phone hash, and this is how the device turns it
/// into "Anna" — the same lookup the board does from the address book,
/// written out once so the extension needs neither Contacts access nor the
/// app running.
///
/// Compiled into both the app and the extension, so Foundation only.
enum NameMap {
    static let appGroup = "group.dev.winktech.moodring"

    /// The App Group container — nil when the process lacks the
    /// entitlement, which an unsigned CI test host does; tests point this
    /// at a temporary directory instead. Nothing else should assign it.
    static var directory: URL? = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroup)

    private static var url: URL? { directory?.appending(path: "names.json") }

    /// Replaces the map. Called by the app whenever it rebuilds its contact
    /// index; a few hundred entries is tens of kilobytes.
    static func write(_ names: [String: String]) {
        guard let url, let data = try? JSONEncoder().encode(names) else { return }
        // Not `.completeFileProtection`: a push arrives on a locked phone,
        // and the extension runs right then. Fully protected files are
        // unreadable until the first unlock after boot, so the name lookup
        // would fail exactly when it matters.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// The first name for a hash, or nil when the sender isn't in the map —
    /// a contact removed since the last sync, or a map never written.
    static func name(for hash: String) -> String? {
        guard let url, let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        return names[hash]
    }
}
