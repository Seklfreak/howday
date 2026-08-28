import CryptoKit
import Foundation

enum PhoneNumber {
    /// E.164 with leading + ("+15551234567") from a picked country and the
    /// number as typed nationally, as the Supabase auth API expects. Returns
    /// nil while the digits can't be a phone number yet — which is what keeps
    /// the "Send code" button disabled.
    static func e164(country: CountryCode, national: String) -> String? {
        // People type their number the way they'd dial it at home, and the
        // national trunk prefix is not part of E.164. (Italy is the one place
        // that keeps its leading 0 — on landlines, which can't take an SMS.)
        let digits = national.filter(\.isNumber).drop(while: { $0 == "0" })
        let full = "\(country.dial)\(digits)"
        guard digits.count >= 4, full.count <= 15 else { return nil }
        return "+" + full
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
