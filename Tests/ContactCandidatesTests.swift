import Testing
@testable import Howday

/// `ContactDirectory.candidates` turns a number as saved in the address book
/// into the E.164-without-plus forms worth hashing. Every one of these was a
/// real miss at some point.
struct ContactCandidatesTests {
    private let germany = 49
    private let unitedStates = 1

    @Test func internationalFormsAreTakenAsWritten() {
        #expect(ContactDirectory.candidates(for: "+49 176 1234567", homeDial: germany) == ["491761234567"])
        #expect(ContactDirectory.candidates(for: "0049 176 1234567", homeDial: germany) == ["491761234567"])
        // A foreign number in a German address book keeps its own code.
        #expect(ContactDirectory.candidates(for: "+1 (555) 123-4567", homeDial: germany) == ["15551234567"])
    }

    @Test func nationalFormGetsTheHomeCallingCode() {
        // The way most people outside the NANP save most numbers — and
        // before homeDial existed, every one of them silently failed.
        #expect(ContactDirectory.candidates(for: "0176 1234567", homeDial: germany) == ["491761234567"])
    }

    @Test func noCandidateEverStartsWithZero() {
        // No calling code starts with 0, so such a candidate can never
        // equal a stored number — hashing it would only be wasted work.
        for raw in ["0176 1234567", "0049 176 1234567", "0 176 1234567"] {
            for candidate in ContactDirectory.candidates(for: raw, homeDial: germany) {
                #expect(!candidate.hasPrefix("0"), "\(raw) produced \(candidate)")
            }
        }
    }

    @Test func ambiguousDigitsGetBothReadings() {
        // "176…" could be German national without a trunk zero, or an
        // international number with the + left off; both are hashed.
        let candidates = Set(ContactDirectory.candidates(for: "176 1234567", homeDial: germany))
        #expect(candidates == ["1761234567", "491761234567"])
    }

    @Test func nanpLengthRulesOutANationalReading() {
        // Seven digits under +1 is a local number saved without its area
        // code; prefixing it would invent a number nobody has.
        #expect(ContactDirectory.candidates(for: "555-1234", homeDial: unitedStates) == ["5551234"])
        let full = Set(ContactDirectory.candidates(for: "(555) 123-4567", homeDial: unitedStates))
        #expect(full == ["5551234567", "15551234567"])
    }

    @Test func tooShortToBeANumber() {
        #expect(ContactDirectory.candidates(for: "12345", homeDial: germany).isEmpty)
        #expect(ContactDirectory.candidates(for: "", homeDial: germany).isEmpty)
    }
}
