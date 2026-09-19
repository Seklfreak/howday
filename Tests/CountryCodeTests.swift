import Testing
@testable import Howday

struct CountryCodeTests {
    @Test func sharedCodesResolveToTheMainCountry() {
        #expect(CountryCode.forDial(1)?.region == "US")
        #expect(CountryCode.forDial(44)?.region == "GB")
        #expect(CountryCode.forDial(49)?.region == "DE")
        #expect(CountryCode.forDial(999) == nil)
    }

    @Test func splitPrefersTheLongestCallingCode() {
        let germany = CountryCode.split(internationalDigits: "491761234567")
        #expect(germany?.country.region == "DE")
        #expect(germany?.national == "1761234567")

        // 358 is Finland; a two-digit read (35) would be wrong.
        let finland = CountryCode.split(internationalDigits: "358401234567")
        #expect(finland?.country.region == "FI")
        #expect(finland?.national == "401234567")
    }

    @Test func internationalFormIsDetectedByPlusOrDoubleZero() {
        let plus = CountryCode.international(in: "+49 176 1234567")
        #expect(plus?.country.region == "DE")
        #expect(plus?.national == "1761234567")

        let doubleZero = CountryCode.international(in: "0049 176 1234567")
        #expect(doubleZero?.country.region == "DE")
        #expect(doubleZero?.national == "1761234567")
    }

    @Test func nationalFormIsNotInternational() {
        #expect(CountryCode.international(in: "0176 1234567") == nil)
        #expect(CountryCode.international(in: "555 123 4567") == nil)
    }

    @Test func searchFindsTheIsoCodeBeforeNameSubstrings() {
        // "US" by name alone lists every country spelt with a "us" and not
        // the United States; the ISO code has to win.
        #expect(CountryCode.matching(searchText: "us").first?.region == "US")
        #expect(CountryCode.matching(searchText: "UK").first?.region == "GB")
        #expect(CountryCode.matching(searchText: "+1").first?.region == "US")
        #expect(CountryCode.matching(searchText: "").count == CountryCode.all.count)
    }
}
