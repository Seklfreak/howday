import Foundation

/// The pure half of contact matching: turning a number as someone actually
/// saved it into the hashable E.164 forms it might mean. Split out from
/// `ContactDirectory` because it is the one piece with no address book, no
/// network and no actor behind it — which is what lets `ContactCandidatesTests`
/// cover the rules that every silent match failure has come from.
extension ContactDirectory {
    /// Candidate E.164-without-plus forms for a raw contact number. We can't
    /// fully parse national formats without a phone-number library, so we
    /// hash a small candidate set — extra candidates are harmless because
    /// matching is exact, and a guess at the wrong country just produces a
    /// hash nothing matches.
    ///
    /// A number saved the way it is dialled at home ("0176 1234567") carries
    /// no calling code, so it can only be matched by supplying one — which is
    /// what `homeDial` is for. Outside the US that national form is how most
    /// people save most numbers, and every one of them used to miss.
    static func candidates(for raw: String, homeDial: Int) -> [String] {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 7 else { return [] }
        var result: Set<String> = []
        if raw.trimmingCharacters(in: .whitespaces).hasPrefix("+") {
            result.insert(digits)
        } else if digits.hasPrefix("00") {
            result.insert(String(digits.dropFirst(2)))
        } else if digits.hasPrefix("0") {
            // A trunk prefix, so this is national form and nothing else: no
            // calling code starts with 0, so the digits as written can never
            // equal a stored number and aren't worth hashing.
            insert(national: digits, dial: homeDial, into: &result)
        } else {
            // Ambiguous — either international with the + left off ("49176…")
            // or national in a country that has no trunk prefix (every US
            // number, and a German one saved as "176…"). Both get a candidate.
            result.insert(digits)
            insert(national: digits, dial: homeDial, into: &result)
        }
        return Array(result)
    }

    /// Add `<calling code><national digits>` for a number read as national
    /// form. A length we know contradicts that reading is dropped rather than
    /// hashed: seven digits under +1 is a local number saved without its area
    /// code, and prefixing it only invents a number nobody has.
    private static func insert(national digits: String, dial: Int, into result: inout Set<String>) {
        let national = PhoneNumber.nationalDigits(digits)
        if let expected = PhoneNumber.nationalDigitCount(forDial: dial), national.count != expected { return }
        guard national.count + String(dial).count <= 15 else { return }
        result.insert("\(dial)\(national)")
    }
}
