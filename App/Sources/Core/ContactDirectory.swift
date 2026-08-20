import Contacts
import Foundation
import Supabase
import UIKit

/// The viewer's local address book, powering the contacts-based social
/// graph: phone-number hashes are synced to the server to derive mutual
/// links, while names and photos stay on-device and are looked up here
/// for display.
/// A my_mutuals() row: a mutual contact's user id plus their phone hash,
/// which keys the lookup into the local address book.
private struct MutualRow: Decodable {
    let id: UUID
    let phoneHash: String

    enum CodingKeys: String, CodingKey {
        case id
        case phoneHash = "phone_hash"
    }
}

enum ContactDirectory {
    struct Identity: Sendable, Hashable {
        let name: String
        let photo: Data?
    }

    /// Whether the system permission prompt has been answered (either way).
    static var hasBeenAsked: Bool {
        CNContactStore.authorizationStatus(for: .contacts) != .notDetermined
    }

    static var isAuthorized: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if #available(iOS 18, *), status == .limited { return true }
        return status == .authorized
    }

    /// Request access if not yet determined; no-op prompt otherwise.
    @discardableResult
    static func requestAccess() async -> Bool {
        let granted = try? await CNContactStore().requestAccess(for: .contacts)
        return granted ?? false
    }

    /// Serializes the cached address-book index and the sync-staleness flag.
    private actor State {
        private(set) var index: [String: Identity]?
        private(set) var needsSync = true

        func setIndex(_ new: [String: Identity]) { index = new }
        func clearNeedsSync() { needsSync = false }
        func markDirty(dropIndex: Bool) {
            needsSync = true
            if dropIndex { index = nil }
        }
    }

    private static let state = State()

    /// Staleness hooks, installed on first use: returning to the foreground
    /// re-syncs (the cheap way to keep links fresh for friends), and an
    /// address-book edit additionally drops the cached name/photo index.
    private static let observers: [NSObjectProtocol] = [
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
        ) { _ in
            Task {
                await state.markDirty(dropIndex: false)
                await syncIfNeeded()
            }
        },
        NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: nil
        ) { _ in
            Task {
                await state.markDirty(dropIndex: true)
                await syncIfNeeded()
            }
        },
    ]

    /// Replace the server's view of who this user knows with the current
    /// address book (hashes only) — at most once per foreground session or
    /// contacts change, so it's cheap to call from every board load. On
    /// failure the staleness flag stays set and the next call retries.
    static func syncIfNeeded() async {
        _ = observers
        guard isAuthorized,
              (try? await Supa.client.auth.session) != nil,
              await state.needsSync else { return }
        do {
            let index = try await currentIndex()
            struct SyncResult: Decodable { let linked: Int }
            let _: SyncResult = try await Supa.client.functions.invoke(
                "sync-contacts",
                options: FunctionInvokeOptions(body: ["hashes": Array(index.keys)])
            )
            await state.clearNeedsSync()
        } catch {
            // Stale links only mean stale visibility; the retry is free.
        }
    }

    /// The caller's mutual contacts with locally-resolved identities. Does
    /// NOT sync — two cheap calls (cached index + one RPC), safe to run on
    /// every board refresh and realtime event.
    static func fetchMutuals() async throws -> [(id: UUID, identity: Identity)] {
        guard isAuthorized else { throw DirectoryError.accessDenied }
        let index = try await currentIndex()
        let mutuals: [MutualRow] = try await Supa.client
            .rpc("my_mutuals")
            .execute()
            .value
        return mutuals.map {
            ($0.id, index[$0.phoneHash] ?? Identity(name: "Friend", photo: nil))
        }
    }

    /// The address-book index, rebuilt only after a contacts change.
    private static func currentIndex() async throws -> [String: Identity] {
        if let cached = await state.index { return cached }
        let built = try await localIndex()
        await state.setIndex(built)
        return built
    }

    enum DirectoryError: LocalizedError {
        case accessDenied
        var errorDescription: String? {
            "Moodring is contacts-based — enable contacts access in Settings to see your friends."
        }
    }

    /// Hash → identity for every contact phone number, built off the main
    /// actor since enumerating a big contact list is slow.
    private static func localIndex() async throws -> [String: Identity] {
        try await Task.detached(priority: .userInitiated) {
            let keys = [
                CNContactGivenNameKey, CNContactFamilyNameKey,
                CNContactPhoneNumbersKey, CNContactThumbnailImageDataKey,
            ] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var index: [String: Identity] = [:]
            try CNContactStore().enumerateContacts(with: request) { contact, _ in
                // Friends are shown by first name, like the address book would.
                let name = contact.givenName.isEmpty
                    ? (contact.familyName.isEmpty ? "Friend" : contact.familyName)
                    : contact.givenName
                let identity = Identity(name: name, photo: contact.thumbnailImageData)
                for phone in contact.phoneNumbers {
                    for candidate in candidates(for: phone.value.stringValue) {
                        index[PhoneNumber.hashForMatching(e164: candidate)] = identity
                    }
                }
            }
            return index
        }.value
    }

    /// Candidate E.164-without-plus forms for a raw contact number. We can't
    /// fully parse national formats without a phone-number library, so we
    /// hash a small candidate set — extra candidates are harmless because
    /// matching is exact.
    /// Known limitation: nationally-formatted non-US numbers (e.g. a German
    /// contact saved as 0176…) won't match; saved with +49… they will.
    private static func candidates(for raw: String) -> [String] {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 7 else { return [] }
        var result: Set<String> = []
        if raw.trimmingCharacters(in: .whitespaces).hasPrefix("+") {
            result.insert(digits)
        } else if digits.hasPrefix("00") {
            result.insert(String(digits.dropFirst(2)))
        } else {
            result.insert(digits)
            if digits.count == 10 { result.insert("1" + digits) }
        }
        return Array(result)
    }
}
