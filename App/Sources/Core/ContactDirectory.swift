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
    struct Identity: Sendable, Equatable {
        let name: String
        /// Decoded once and cached, not raw thumbnail bytes: the board
        /// rebuilds on every realtime check-in, and re-decoding every
        /// friend's photo each time was pure main-thread churn.
        let avatar: Avatar?
        /// The matched number as saved in the address book, for sms: links.
        let phone: String?
    }

    /// What the hash index holds per contact. Deliberately no image data —
    /// see `localIndex`.
    private struct ContactRef: Sendable, Equatable {
        let identifier: String
        let name: String
        let phone: String?
    }

    /// How many contacts with a phone number the app can currently read —
    /// distinct contacts, not numbers. Comes from the cached index, so it is
    /// free after the first board load. Contacts without a number are not
    /// counted: they could never match anyone anyway.
    static func visibleContactCount() async -> Int? {
        guard let index = try? await currentIndex() else { return nil }
        return Set(index.values.map(\.identifier)).count
    }

    /// How many mutual contacts the server links to this account — Settings'
    /// "3 of your contacts are on Howday". Server-side only: it reads no
    /// address book, so the number is still right with contacts access off,
    /// where the board itself can show nothing.
    static func mutualCount() async throws -> Int {
        let mutuals: [MutualRow] = try await Supa.client
            .rpc("my_mutuals")
            .execute()
            .value
        return mutuals.count
    }

    /// The address book changed under the app's feet — after the limited
    /// access picker adds contacts, for one. The system posts
    /// CNContactStoreDidChange for that too, but not before the picker's
    /// completion runs, and a reload racing it would read the stale index.
    static func noteAddressBookChanged() async {
        await state.markDirty()
    }

    /// Serializes the cached address-book index and the sync-staleness flag.
    private actor State {
        private(set) var index: [String: ContactRef]?
        private(set) var needsSync = true
        private var lastSync: Task<Bool, Never>?
        /// Contact identifier -> decoded avatar, `nil` meaning "looked, no
        /// photo". Only ever holds the handful of contacts on the board.
        private var avatars: [String: Avatar?] = [:]

        func setIndex(_ new: [String: ContactRef]) { index = new }
        func clearNeedsSync() { needsSync = false }

        func unresolvedAvatars(_ identifiers: [String]) -> [String] {
            identifiers.filter { avatars.index(forKey: $0) == nil }
        }

        /// Records misses too, so a contact without a photo isn't re-fetched
        /// on every board load.
        func cacheAvatars(_ found: [String: Avatar], requested: [String]) {
            for id in requested { avatars[id] = found[id] }
        }

        func avatar(_ identifier: String) -> Avatar? { avatars[identifier] ?? nil }
        /// Both staleness hooks drop the index. A contact added while the app
        /// was suspended never delivers CNContactStoreDidChange, so keeping
        /// the cached index across a foreground meant that contact stayed
        /// invisible until the next cold launch. Re-reading the address book
        /// is off the main actor, no longer gates the board, and the
        /// fingerprint check keeps it from becoming an upload.
        func markDirty() {
            needsSync = true
            index = nil
            // A changed address book can mean a changed photo, and these
            // are keyed by contact identifier, which survives an edit.
            avatars.removeAll()
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
    ///
    /// `force` uploads even when the address book hasn't changed — the only
    /// way to re-link a contact who signed up since the last upload, whose
    /// number was already saved then, so the fingerprint is current and every
    /// automatic path skips. For an explicit user gesture only; the server
    /// backfills those links on signup now (backfill_links_on_signup), so
    /// this is the retry for anyone who registered before that shipped.
    @discardableResult
    static func syncIfNeeded(force: Bool = false) async -> Bool {
        _ = observers
        guard isAuthorized,
              let session = try? await Supa.client.auth.session else { return false }
        // Dropping the cached index is half of what force means: a manual
        // refresh should see contacts added while the app was suspended.
        if force { await state.markDirty() }
        guard await state.needsSync else { return false }
        let userId = session.user.id
        return await state.enqueueSync {
            // Read first: `await` cannot sit to the right of `||`, which
            // makes it an autoclosure the actor can't be touched from.
            let stillStale = await state.needsSync
            guard force || stillStale else { return false }
            do {
                let index = try await currentIndex()
                let hashes = Array(index.keys)
                let fingerprint = fingerprint(of: hashes, userId: userId)
                guard force || needsUpload(fingerprint: fingerprint) else {
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
        let refs = mutuals.compactMap { index[$0.phoneHash] }
        try await resolveAvatars(for: refs.map(\.identifier))
        var resolved: [(id: UUID, identity: Identity)] = []
        resolved.reserveCapacity(mutuals.count)
        for row in mutuals {
            guard let ref = index[row.phoneHash] else {
                resolved.append((id: row.id, identity: Identity(name: "Friend", avatar: nil, phone: nil)))
                continue
            }
            resolved.append((
                id: row.id,
                identity: Identity(
                    name: ref.name,
                    avatar: await state.avatar(ref.identifier),
                    phone: ref.phone
                )
            ))
        }
        return resolved
    }

    /// Photos for the people actually on the board — a handful — rather than
    /// for the whole address book. One batched store call, then cached until
    /// the contacts change, because a friend checking in reloads the board.
    private static func resolveAvatars(for identifiers: [String]) async throws {
        let missing = await state.unresolvedAvatars(identifiers)
        guard !missing.isEmpty else { return }
        let found = try await Task.detached(priority: .utility) { () -> [String: Avatar] in
            let contacts = try CNContactStore().unifiedContacts(
                matching: CNContact.predicateForContacts(withIdentifiers: missing),
                keysToFetch: [CNContactThumbnailImageDataKey as CNKeyDescriptor]
            )
            // Decoding here, off the main actor: UIImage(data:) is lazy, so
            // leaving it to the card's body put a decode of every thumbnail
            // on the main thread, again on every scroll pass and reload.
            return contacts.reduce(into: [:]) { result, contact in
                guard let data = contact.thumbnailImageData,
                      let image = UIImage(data: data) else { return }
                result[contact.identifier] = Avatar(image: image.preparingForDisplay() ?? image)
            }
        }.value
        await state.cacheAvatars(found, requested: missing)
    }

    /// The address-book index, rebuilt only after a contacts change.
    private static func currentIndex() async throws -> [String: ContactRef] {
        if let cached = await state.index { return cached }
        let built = try await localIndex(homeDial: await homeDial())
        await state.setIndex(built)
        // The notification extension names a push's sender from this: the
        // server sends the sender's hash, the map turns it into the first
        // name the board would show. Rewritten on every index build, so an
        // edited contact is renamed in the next push too.
        NameMap.write(built.mapValues(\.name))
        return built
    }

    /// The calling code the address book's national-format numbers are most
    /// likely missing. The signed-in user's own number answers that better
    /// than the device region does — contacts are overwhelmingly from the
    /// owner's own country, and a German number stays German on a phone set
    /// to the US region — so the region is only the fallback, for the window
    /// before sign-in and for an account with no phone on it.
    private static func homeDial() async -> Int {
        // Supabase stores the phone as E.164 without the leading +.
        if let phone = try? await Supa.client.auth.session.user.phone,
           let match = CountryCode.split(internationalDigits: phone.filter(\.isNumber)) {
            return match.country.dial
        }
        return CountryCode.deviceDefault.dial
    }

    /// Hash → contact for every phone number in the address book, built off
    /// the main actor since enumerating a big contact list is slow.
    ///
    /// Deliberately does NOT ask for thumbnails: this sweep exists to produce
    /// hashes and runs on every foreground, so pulling image data for
    /// hundreds of contacts to use it for the handful who turn out to be
    /// mutual was most of its cost — and it competed with the refresh
    /// animation. `resolveAvatars` fetches those afterwards.
    ///
    /// `.utility`, not `.userInitiated`: nothing on screen waits for this —
    /// the board renders from the links the previous sync established — so
    /// it should yield to whatever the user is currently looking at.
    private static func localIndex(homeDial: Int) async throws -> [String: ContactRef] {
        try await Task.detached(priority: .utility) {
            let keys = [
                CNContactIdentifierKey, CNContactGivenNameKey,
                CNContactFamilyNameKey, CNContactPhoneNumbersKey,
            ] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var index: [String: ContactRef] = [:]
            try CNContactStore().enumerateContacts(with: request) { contact, _ in
                // Friends are shown by first name, like the address book would.
                let name = contact.givenName.isEmpty
                    ? (contact.familyName.isEmpty ? "Friend" : contact.familyName)
                    : contact.givenName
                for phone in contact.phoneNumbers {
                    let ref = ContactRef(
                        identifier: contact.identifier,
                        name: name,
                        phone: phone.value.stringValue
                    )
                    for candidate in candidates(for: phone.value.stringValue, homeDial: homeDial) {
                        index[PhoneNumber.hashForMatching(e164: candidate)] = ref
                    }
                }
            }
            return index
        }.value
    }
}
