import SwiftUI

enum Mood: Int, CaseIterable, Identifiable, Sendable {
    case rough = 1
    case low = 2
    case okay = 3
    case good = 4
    case great = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .rough: "Rough"
        case .low: "Low"
        case .okay: "Okay"
        case .good: "Good"
        case .great: "Great"
        }
    }

    var color: Color {
        switch self {
        case .rough: Color(red: 0.357, green: 0.431, blue: 0.659)
        case .low: Color(red: 0.431, green: 0.576, blue: 0.671)
        case .okay: Color(red: 0.604, green: 0.682, blue: 0.494)
        case .good: Color(red: 0.875, green: 0.659, blue: 0.306)
        case .great: Color(red: 0.910, green: 0.529, blue: 0.235)
        }
    }
}
