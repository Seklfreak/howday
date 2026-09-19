import Contacts
import Foundation

/// The contacts permission, as the rest of the app needs to read it. Split
/// from ContactDirectory only for file length; nothing here touches the
/// address book itself.
extension ContactDirectory {
    /// Whether the system permission prompt has been answered (either way).
    static var hasBeenAsked: Bool {
        CNContactStore.authorizationStatus(for: .contacts) != .notDetermined
    }

    static var isAuthorized: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if #available(iOS 18, *), status == .limited { return true }
        return status == .authorized
    }

    /// iOS 18's "Select Contacts": access is granted, but only to the
    /// contacts the user picked. The sync treats it as authorized (it is —
    /// for those contacts); the board has to say so, because the friends
    /// outside the selection are simply missing with nothing to explain why.
    static var isLimited: Bool {
        if #available(iOS 18, *) {
            return CNContactStore.authorizationStatus(for: .contacts) == .limited
        }
        return false
    }

    /// Request access if not yet determined; no-op prompt otherwise.
    @discardableResult
    static func requestAccess() async -> Bool {
        let granted = try? await CNContactStore().requestAccess(for: .contacts)
        return granted ?? false
    }

    enum DirectoryError: LocalizedError {
        case accessDenied
        var errorDescription: String? {
            "Howday is contacts-based — enable contacts access in Settings to see your friends."
        }
    }
}
