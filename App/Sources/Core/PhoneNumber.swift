import CryptoKit
import Foundation

enum PhoneNumber {
    /// Every country on the North American Numbering Plan (+1 — the US,
    /// Canada, much of the Caribbean) uses exactly ten national digits.
    static let nanpNationalDigits = 10

    /// How many national digits a calling code takes, where we are sure of it.
    /// Nil means "nothing tighter than E.164's own bounds" — most of the
    /// world, where the length varies by carrier and a guess would reject
    /// somebody's real number.
    ///
    /// +1 is worth knowing exactly: it is what most people here will type,
    /// and it is what App Review dials. A number one digit short otherwise
    /// spends an SMS and comes back as a Twilio 60200 nobody can read.
    static func nationalDigitCount(forDial dial: Int) -> Int? {
        dial == 1 ? nanpNationalDigits : nil
    }

    /// The national digits as E.164 counts them: separators gone, and without
    /// the trunk prefix people dial at home. (Italy is the one place that
    /// keeps its leading 0 — on landlines, which can't take an SMS.)
    static func nationalDigits(_ national: String) -> String {
        String(national.filter(\.isNumber).drop(while: { $0 == "0" }))
    }

    /// E.164 with leading + ("+15551234567") from a picked country and the
    /// number as typed nationally, as the Supabase auth API expects. Returns
    /// nil while the digits can't be a phone number yet — which is what keeps
    /// the "Send code" button disabled.
    static func e164(country: CountryCode, national: String) -> String? {
        let digits = nationalDigits(national)
        let full = "\(country.dial)\(digits)"
        guard digits.count >= 4, full.count <= 15 else { return nil }
        if let expected = nationalDigitCount(forDial: country.dial), digits.count != expected { return nil }
        return "+" + full
    }

    /// SHA-256 hex of the number in the format Supabase stores in
    /// auth.users.phone: E.164 WITHOUT the leading + ("15551234567").
    /// The signup trigger hashes that stored value, so contact matching
    /// (M2) must hash the identical form or nothing ever matches.
    static func hashForMatching(e164: String) -> String {
        let stored = e164.hasPrefix("+") ? String(e164.dropFirst()) : e164
        return SHA256.hash(data: Data(stored.utf8)).hexString
    }
}

extension Digest {
    /// Lowercase hex, the form the server stores. Hand-rolled because
    /// `String(format: "%02x")` per byte is ~30x slower, and building the
    /// contact index hashes every phone number in the address book.
    var hexString: String {
        let digits = Array("0123456789abcdef".utf8)
        var characters: [UInt8] = []
        characters.reserveCapacity(Self.byteCount * 2)
        for byte in self {
            characters.append(digits[Int(byte >> 4)])
            characters.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: characters, as: UTF8.self)
    }
}
