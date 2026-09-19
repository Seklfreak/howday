import Testing
@testable import Howday

struct PhoneNumberTests {
    private let germany = CountryCode(region: "DE", dial: 49)
    private let unitedStates = CountryCode(region: "US", dial: 1)

    @Test func nationalDigitsDropSeparatorsAndTrunkZero() {
        #expect(PhoneNumber.nationalDigits("0176 123 4567") == "1761234567")
        #expect(PhoneNumber.nationalDigits("(555) 123-4567") == "5551234567")
        #expect(PhoneNumber.nationalDigits("00 176") == "176")
    }

    @Test func e164DropsTheTrunkZero() {
        #expect(PhoneNumber.e164(country: germany, national: "0176 1234567") == "+491761234567")
        #expect(PhoneNumber.e164(country: germany, national: "176 1234567") == "+491761234567")
    }

    @Test func nanpNumbersMustHaveTenDigits() {
        #expect(PhoneNumber.e164(country: unitedStates, national: "(555) 123-4567") == "+15551234567")
        #expect(PhoneNumber.e164(country: unitedStates, national: "555 1234") == nil)
        #expect(PhoneNumber.e164(country: unitedStates, national: "555 123 45678") == nil)
    }

    @Test func e164RejectsTooShortAndTooLong() {
        #expect(PhoneNumber.e164(country: germany, national: "123") == nil)
        // 2 + 14 = 16 digits, one past E.164's limit.
        #expect(PhoneNumber.e164(country: germany, national: "12345678901234") == nil)
        #expect(PhoneNumber.e164(country: germany, national: "1234567890123") == "+491234567890123")
    }

    /// Pinned to the digest of the form Supabase stores (`auth.users.phone`
    /// is E.164 without the `+`): if this ever changes, the signup trigger
    /// and the client hash different strings and nobody matches anyone.
    @Test func hashMatchesTheStoredForm() {
        let expected = "d6736136ea896c1bfdc553e0e86e702c70d060d805696ca3e4e9e0961353860a"
        #expect(PhoneNumber.hashForMatching(e164: "+15551234567") == expected)
        #expect(PhoneNumber.hashForMatching(e164: "15551234567") == expected)
    }
}
