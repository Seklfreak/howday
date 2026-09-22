import Foundation
import Testing
@testable import Howday

struct PushTextTests {
    @Test func eachKindNamesTheSender() {
        #expect(PushText.body(name: "Anna", kind: "new") == "Anna just checked in 💫")
        #expect(PushText.body(name: "Anna", kind: "update") == "Anna's emoji changed 💫")
        #expect(PushText.body(name: "Anna", kind: "join") == "Anna joined Howday 👋")
    }

    @Test func unknownKindFallsBackToCheckedIn() {
        #expect(PushText.body(name: "Anna", kind: nil) == "Anna just checked in 💫")
        #expect(PushText.body(name: "Anna", kind: "something-new") == "Anna just checked in 💫")
    }
}

/// Under a temporary directory rather than the App Group container: the CI
/// test host is unsigned, so it has no entitlements and no container.
@Suite(.serialized)
struct NameMapTests {
    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "NameMapTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NameMap.directory = directory
    }

    @Test func roundTripsThroughTheGroupContainer() {
        NameMap.write(["abc": "Anna", "def": "Ben"])
        #expect(NameMap.name(for: "abc") == "Anna")
        #expect(NameMap.name(for: "def") == "Ben")
        #expect(NameMap.name(for: "zzz") == nil)
    }

    @Test func aRewriteReplacesRatherThanMerges() {
        NameMap.write(["abc": "Anna"])
        NameMap.write(["def": "Ben"])
        #expect(NameMap.name(for: "abc") == nil)
        #expect(NameMap.name(for: "def") == "Ben")
    }
}

/// The `source` values are what the dashboard groups by, and the URL is the
/// only channel carrying them from a widget into the app — a typo either
/// side silently loses the attribution rather than failing.
struct WidgetSourceTests {
    @Test func everySourceSurvivesTheRoundTrip() {
        let all: [WidgetSource] = [.skySmall, .skyMedium, .skyLarge, .lockCircular, .lockRectangular, .control, .app]
        for source in all {
            let url = source.openURL
            #expect(url != nil, "\(source.rawValue)")
            #expect(WidgetSource.from(openURL: url!) == source, "\(source.rawValue)")
        }
    }

    @Test func aForeignURLIsNotAnOpen() {
        #expect(WidgetSource.from(openURL: URL(string: "https://example.com/open?source=sky-small")!) == nil)
        #expect(WidgetSource.from(openURL: URL(string: "howday://other?source=sky-small")!) == nil)
        #expect(WidgetSource.from(openURL: URL(string: "howday://open")!) == nil)
        #expect(WidgetSource.from(openURL: URL(string: "howday://open?source=nonsense")!) == nil)
    }
}
