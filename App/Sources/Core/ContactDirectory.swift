import Contacts
import CryptoKit
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
        /// The matched number as saved in the address book, for sms: links.
        let phone: String?
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
        private var lastSync: Task<Bool, Never>?

        func setIndex(_ new: [String: Identity]) { index = new }
        func clearNeedsSync() { needsSync = false }
        /// Both staleness hooks drop the index. A contact added while the app
        /// was suspended never delivers CNContactStoreDidChange, so keeping
        /// the cached index across a foreground meant that contact stayed
        /// invisible until the next cold launch. Re-reading the address book
        /// is off the main actor, no longer gates the board, and the
        /// fingerprint check keeps it from becoming an upload.
        func markDirty() {
            needsSync = true
            index = nil
        }

        /// Chain sync attempts instead of running them concurrently: board
        /// load, foregrounding, and a contacts change can all fire at once,
        /// and parallel sync-contacts calls raced each other server-side.
        /// Each queued attempt re-checks needsSync, so followers of a
        /// successful sync are no-ops while a mid-flight contacts change
        /// still gets a fresh upload afterwards.
        func enqueueSync(_ attempt: @escaping @Sendable () async -> Bool) -> Task<Bool, Never> {
            let previous = lastSync
            let task = Task {
                _ = await previous?.value
                return await attempt()
            }
            lastSync = task
            return task
        }
    }

    private static let state = State()

    /// Staleness hooks, installed on first use: both returning to the
    /// foreground and an address-book edit re-read the address book. Neither
    /// forces an upload — that is syncIfNeeded's fingerprint check, which is
    /// what makes them cheap enough to run this often.
    private static let observers: [NSObjectProtocol] = [
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
        ) { _ in
            Task {
                await state.markDirty()
                await syncIfNeeded()
            }
        },
        NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: nil
        ) { _ in
            Task {
                await state.markDirty()
                await syncIfNeeded()
            }
        },
    ]

    /// How long a successful upload stays good even when nothing in the
    /// address book changed. Re-uploading is what eventually links a contact
    /// who signed up *after* the last one — slow-moving enough that it does
    /// not justify paying the round trip on every foreground.
    private static let maxSyncAge: TimeInterval = 24 * 60 * 60
    private static let fingerprintKey = "contacts.syncFingerprint"
    private static let syncedAtKey = "contacts.syncedAt"

    /// Replace the server's view of who this user knows with the current
    /// address book (hashes only). Returns true when an upload actually
    /// happened, so callers can refresh whatever they derived from the links.
    ///
    /// Cheap to call from every board load and every foreground: an address
    /// book that hashes to what was last uploaded skips the request, which is
    /// a ~1.4s round trip at p50 (3s at p95) carrying the whole hash set.
    /// On failure the staleness flag stays set and the next call retries.
    @discardableResult
    static func syncIfNeeded() async -> Bool {
        _ = observers
        guard isAuthorized,
              let session = try? await Supa.client.auth.session,
              await state.needsSync else { return false }
        let userId = session.user.id
        return await state.enqueueSync {
            guard await state.needsSync else { return false }
            do {
                let index = try await currentIndex()
                let hashes = Array(index.keys)
                let fingerprint = fingerprint(of: hashes, userId: userId)
                guard needsUpload(fingerprint: fingerprint) else {
                    await state.clearNeedsSync()
                    return false
                }
                try await withTrace("contacts.sync") {
                    struct SyncResult: Decodable { let linked: Int }
                    let _: SyncResult = try await Supa.client.functions.invoke(
                        "sync-contacts",
                        options: FunctionInvokeOptions(body: ["hashes": hashes])
                    )
                }
                recordUpload(fingerprint: fingerprint)
                await state.clearNeedsSync()
                return true
            } catch {
                // Stale links only mean stale visibility; the retry is free.
                return false
            }
        }.value
    }

    /// Whether these hashes differ from the last upload, or that upload has
    /// aged out. A missing fingerprint or timestamp means we don't know what
    /// the server holds, so upload.
    private static func needsUpload(fingerprint: String) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: fingerprintKey) == fingerprint,
              let syncedAt = defaults.object(forKey: syncedAtKey) as? Date else { return true }
        let age = Date.now.timeIntervalSince(syncedAt)
        // A clock moved backwards reads as a negative age — treat that as
        // stale rather than trusting it for the next day.
        return age < 0 || age >= maxSyncAge
    }

    private static func recordUpload(fingerprint: String) {
        UserDefaults.standard.set(fingerprint, forKey: fingerprintKey)
        UserDefaults.standard.set(Date.now, forKey: syncedAtKey)
    }

    /// Digest of what an upload would send, so an unchanged address book is
    /// recognisable without keeping a second copy of the hashes around.
    /// Sorted, because a dictionary's key order isn't stable between runs;
    /// keyed by user id, because the same address book belongs to different
    /// links after a sign-out and back in as someone else.
    private static func fingerprint(of hashes: [String], userId: UUID) -> String {
        var digest = SHA256()
        digest.update(data: Data(userId.uuidString.utf8))
        for hash in hashes.sorted() { digest.update(data: Data(hash.utf8)) }
        return digest.finalize().hexString
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
            ($0.id, index[$0.phoneHash] ?? Identity(name: "Friend", photo: nil, phone: nil))
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
            "Howday is contacts-based — enable contacts access in Settings to see your friends."
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
                for phone in contact.phoneNumbers {
                    let identity = Identity(
                        name: name,
                        photo: contact.thumbnailImageData,
                        phone: phone.value.stringValue
                    )
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
