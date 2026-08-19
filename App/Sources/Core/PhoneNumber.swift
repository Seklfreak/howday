import CryptoKit
import Foundation

enum PhoneNumber {
    /// E.164 with leading +, as the Supabase auth API expects ("+15551234567").
    /// The user must include their country code; we only strip formatting.
    static func e164(from input: String) -> String? {
        let digits = input.filter(\.isNumber)
        guard digits.count >= 8, digits.count <= 15 else { return nil }
        return "+" + digits
    }

    /// SHA-256 hex of the number in the format Supabase stores in
    /// auth.users.phone: E.164 WITHOUT the leading + ("15551234567").
    /// The signup trigger hashes that stored value, so contact matching
    /// (M2) must hash the identical form or nothing ever matches.
    static func hashForMatching(e164: String) -> String {
        let stored = e164.hasPrefix("+") ? String(e164.dropFirst()) : e164
        let digest = SHA256.hash(data: Data(stored.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
