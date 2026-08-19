import Contacts
import Foundation
import Supabase

struct ContactMatch: Identifiable, Sendable {
    let profileId: UUID
    let displayName: String
    let contactName: String
    var id: UUID { profileId }
}

/// Match-and-discard contact discovery: read contacts, hash candidate
/// number forms on-device, send only the hashes to the match-contacts
/// Edge Function, map matches back to local contact names.
enum ContactMatcher {
    static func findMatches() async throws -> [ContactMatch] {
        let store = CNContactStore()
        let granted = try await store.requestAccess(for: .contacts)
        guard granted else { throw MatchError.accessDenied }

        // Hash → contact display name, built off the main actor since
        // enumerating a big contact list is slow.
        let hashToName = try await Task.detached(priority: .userInitiated) {
            try collectHashes(store: store)
        }.value
        guard !hashToName.isEmpty else { return [] }

        struct Response: Decodable {
            struct Match: Decodable {
                let id: UUID
                let displayName: String
                let phoneHash: String
                enum CodingKeys: String, CodingKey {
                    case id
                    case displayName = "display_name"
                    case phoneHash = "phone_hash"
                }
            }
            let matches: [Match]
        }
        let response: Response = try await Supa.client.functions.invoke(
            "match-contacts",
            options: FunctionInvokeOptions(body: ["hashes": Array(hashToName.keys)])
        )
        return response.matches.map {
            ContactMatch(
                profileId: $0.id,
                displayName: $0.displayName,
                contactName: hashToName[$0.phoneHash] ?? "Contact"
            )
        }
    }

    enum MatchError: LocalizedError {
        case accessDenied
        var errorDescription: String? {
            "Contacts access is off for Moodring. You can still add friends with invite codes, or enable access in Settings."
        }
    }

    private static func collectHashes(store: CNContactStore) throws -> [String: String] {
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey,
        ] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var hashToName: [String: String] = [:]
        try store.enumerateContacts(with: request) { contact, _ in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }.joined(separator: " ")
            for phone in contact.phoneNumbers {
                for candidate in candidates(for: phone.value.stringValue) {
                    hashToName[PhoneNumber.hashForMatching(e164: candidate)] =
                        name.isEmpty ? "Contact" : name
                }
            }
        }
        return hashToName
    }

    /// Candidate E.164-without-plus forms for a raw contact number. We can't
    /// fully parse national formats without a phone-number library, so we
    /// hash a small candidate set — extra candidates are harmless because
    /// matching is exact and nothing is stored server-side.
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
