import Foundation

/// One row of the sign-in country picker: an ISO region and its calling code.
/// Only the code is carried here — the name and flag come from the region, so
/// they follow the device language without a translation table.
struct CountryCode: Identifiable, Hashable {
    let region: String
    let dial: Int

    var id: String { region }

    /// The localized country name ("Germany", "Deutschland", …).
    var name: String {
        Locale.current.localizedString(forRegionCode: region) ?? region
    }

    var dialText: String { "+\(dial)" }

    /// 🇩🇪 — the region's two letters as regional indicator symbols.
    var flag: String {
        String(String.UnicodeScalarView(region.unicodeScalars.compactMap {
            Unicode.Scalar(0x1F1E6 - 65 + $0.value)
        }))
    }
}

extension CountryCode {
    /// The fallback when the device region isn't a country we know a code for.
    static let fallback = CountryCode(region: "US", dial: 1)

    /// Every country, sorted by localized name — the picker's contents.
    static let all: [CountryCode] = dialCodes
        .map { CountryCode(region: $0.key, dial: $0.value) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    /// What the picker starts on: the device's own region, so the common case
    /// is typing the number alone.
    static var deviceDefault: CountryCode {
        guard let region = Locale.current.region?.identifier else { return fallback }
        return all.first { $0.region == region } ?? fallback
    }

    /// The country to show for a calling code. Codes shared by many regions
    /// (+1, +44, …) resolve to the main one rather than whichever sorted first.
    static func forDial(_ dial: Int) -> CountryCode? {
        if let region = shared[dial] { return all.first { $0.region == region } }
        return all.first { $0.dial == dial }
    }

    /// Splits digits typed in international form: "49176…" → (Germany, "176…").
    /// Longest calling code wins, so +1 doesn't swallow +1264.
    static func split(internationalDigits digits: String) -> (country: CountryCode, national: String)? {
        for length in stride(from: 3, through: 1, by: -1) where digits.count > length {
            guard let dial = Int(digits.prefix(length)), let country = forDial(dial) else { continue }
            return (country, String(digits.dropFirst(length)))
        }
        return nil
    }

    /// The picker's search, best match first. A short query is tried as an
    /// ISO code before anything else, because the code is what people type
    /// and it is usually *not* part of the country's own name: searching
    /// "US" by name alone lists Australia, Belarus, Mauritius and Russia —
    /// every country spelt with a "us" except the United States.
    static func matching(searchText: String) -> [CountryCode] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        let digits = query.filter(\.isNumber)
        let region = aliases[query.uppercased()] ?? query.uppercased()

        return all.enumerated()
            .compactMap { position, country -> (key: Int, country: CountryCode)? in
                guard let rank = country.rank(for: query, region: region, digits: digits) else { return nil }
                // `all` is sorted by name already, so folding the position
                // into the key keeps ties alphabetical instead of leaving
                // them to an unstable sort.
                return (rank * all.count + position, country)
            }
            .sorted { $0.key < $1.key }
            .map(\.country)
    }

    /// How well this country answers a search, lower being better; nil when
    /// it doesn't match at all.
    private func rank(for query: String, region: String, digits: String) -> Int? {
        if self.region == region { return 0 }
        if name.range(of: query, options: [.caseInsensitive, .anchored]) != nil { return 1 }
        if name.localizedCaseInsensitiveContains(query) { return 2 }
        guard !digits.isEmpty else { return nil }
        // A typed calling code means the country that owns it: "+1" leads
        // with the United States, not with Anguilla for being alphabetical.
        if dialText == "+" + digits { return CountryCode.forDial(dial)?.region == self.region ? 3 : 4 }
        if dialText.hasPrefix("+" + digits) { return 5 }
        if dialText.contains(digits) { return 6 }
        return nil
    }

    /// What people type when it isn't the ISO code. "UK" is the big one —
    /// the region is GB, and "UK" as a name search finds only Ukraine.
    private static let aliases: [String: String] = ["UK": "GB", "USA": "US", "UAE": "AE"]

    /// Regions that share a calling code — the one a typed or pasted "+code"
    /// resolves to, so the flag isn't a coin flip.
    private static let shared: [Int: String] = [
        1: "US", 7: "RU", 39: "IT", 44: "GB", 47: "NO", 61: "AU", 212: "MA", 262: "RE",
        290: "SH", 358: "FI", 590: "GP", 596: "MQ", 599: "CW", 672: "NF", 970: "PS",
    ]

    /// ISO region → ITU calling code. iOS publishes no calling-code API, so
    /// the table lives here; everything else about a country is derived.
    private static let dialCodes: [String: Int] = [
        "AD": 376, "AE": 971, "AF": 93, "AG": 1, "AI": 1, "AL": 355, "AM": 374, "AO": 244,
        "AR": 54, "AS": 1, "AT": 43, "AU": 61, "AW": 297, "AX": 358, "AZ": 994, "BA": 387,
        "BB": 1, "BD": 880, "BE": 32, "BF": 226, "BG": 359, "BH": 973, "BI": 257, "BJ": 229,
        "BL": 590, "BM": 1, "BN": 673, "BO": 591, "BQ": 599, "BR": 55, "BS": 1, "BT": 975,
        "BW": 267, "BY": 375, "BZ": 501, "CA": 1, "CD": 243, "CF": 236, "CG": 242, "CH": 41,
        "CI": 225, "CK": 682, "CL": 56, "CM": 237, "CN": 86, "CO": 57, "CR": 506, "CU": 53,
        "CV": 238, "CW": 599, "CY": 357, "CZ": 420, "DE": 49, "DJ": 253, "DK": 45, "DM": 1,
        "DO": 1, "DZ": 213, "EC": 593, "EE": 372, "EG": 20, "ER": 291, "ES": 34, "ET": 251,
        "FI": 358, "FJ": 679, "FK": 500, "FM": 691, "FO": 298, "FR": 33, "GA": 241, "GB": 44,
        "GD": 1, "GE": 995, "GF": 594, "GG": 44, "GH": 233, "GI": 350, "GL": 299, "GM": 220,
        "GN": 224, "GP": 590, "GQ": 240, "GR": 30, "GT": 502, "GU": 1, "GW": 245, "GY": 592,
        "HK": 852, "HN": 504, "HR": 385, "HT": 509, "HU": 36, "ID": 62, "IE": 353, "IL": 972,
        "IM": 44, "IN": 91, "IO": 246, "IQ": 964, "IR": 98, "IS": 354, "IT": 39, "JE": 44,
        "JM": 1, "JO": 962, "JP": 81, "KE": 254, "KG": 996, "KH": 855, "KI": 686, "KM": 269,
        "KN": 1, "KP": 850, "KR": 82, "KW": 965, "KY": 1, "KZ": 7, "LA": 856, "LB": 961,
        "LC": 1, "LI": 423, "LK": 94, "LR": 231, "LS": 266, "LT": 370, "LU": 352, "LV": 371,
        "LY": 218, "MA": 212, "MC": 377, "MD": 373, "ME": 382, "MF": 590, "MG": 261, "MH": 692,
        "MK": 389, "ML": 223, "MM": 95, "MN": 976, "MO": 853, "MP": 1, "MQ": 596, "MR": 222,
        "MS": 1, "MT": 356, "MU": 230, "MV": 960, "MW": 265, "MX": 52, "MY": 60, "MZ": 258,
        "NA": 264, "NC": 687, "NE": 227, "NF": 672, "NG": 234, "NI": 505, "NL": 31, "NO": 47,
        "NP": 977, "NR": 674, "NU": 683, "NZ": 64, "OM": 968, "PA": 507, "PE": 51, "PF": 689,
        "PG": 675, "PH": 63, "PK": 92, "PL": 48, "PM": 508, "PR": 1, "PS": 970, "PT": 351,
        "PW": 680, "PY": 595, "QA": 974, "RE": 262, "RO": 40, "RS": 381, "RU": 7, "RW": 250,
        "SA": 966, "SB": 677, "SC": 248, "SD": 249, "SE": 46, "SG": 65, "SH": 290, "SI": 386,
        "SJ": 47, "SK": 421, "SL": 232, "SM": 378, "SN": 221, "SO": 252, "SR": 597, "SS": 211,
        "ST": 239, "SV": 503, "SX": 1, "SY": 963, "SZ": 268, "TC": 1, "TD": 235, "TG": 228,
        "TH": 66, "TJ": 992, "TK": 690, "TL": 670, "TM": 993, "TN": 216, "TO": 676, "TR": 90,
        "TT": 1, "TV": 688, "TW": 886, "TZ": 255, "UA": 380, "UG": 256, "US": 1, "UY": 598,
        "UZ": 998, "VA": 39, "VC": 1, "VE": 58, "VG": 1, "VI": 1, "VN": 84, "VU": 678,
        "WF": 681, "WS": 685, "YE": 967, "YT": 262, "ZA": 27, "ZM": 260, "ZW": 263,
    ]
}
