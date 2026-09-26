import Foundation
import Sentry
import Testing
@testable import Howday

/// Takes events through the Sentry SDK the way a release build does. Debug
/// builds never start the SDK, so without this nothing before TestFlight
/// exercises it — which is how sentry-cocoa 9.29.1 shipped in every 1.28
/// build: it throws an unrecognized selector (`isMetricKitEvent`) while
/// preparing any event, so the first failed request took the app down a
/// second after launch (getsentry/sentry-cocoa#9154). Checked: on 9.29.1
/// this test dies with that exact exception.
///
/// The event goes to `beforeSend` and is dropped there, so nothing leaves
/// the machine; reaching `beforeSend` at all is the proof, since event
/// preparation is what crashed. It is `capture(error:)` rather than a
/// failed request because both go through the same preparation, and a
/// request answered by a stub `URLProtocol` never reaches the SDK's
/// URLSession swizzling — the failed-request capture stays silent.
///
/// On the main actor because that is where the app starts the SDK: from
/// any other thread `SentrySDK.start` hands its setup to the main queue
/// and returns, and an event captured before that runs is dropped.
@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct CrashReportingTests {
    @Test func aReportedErrorIsPreparedWithoutCrashing() async throws {
        let events = startSDK()
        defer { SentrySDK.close() }

        SentrySDK.capture(error: URLError(.badServerResponse))

        let event = try #require(await events.first { _ in true })
        #expect(event.exceptions?.isEmpty == false)
    }

    /// Starts the SDK with the app's own options and a DSN nothing
    /// listens on, and returns every event that reaches `beforeSend`.
    private func startSDK() -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        SentrySDK.start { options in
            CrashReporting.configure(options, dsn: "https://public@sentry.invalid/1")
            // XCTest's own crash reporting stays in charge of this process.
            options.enableCrashHandler = false
            options.beforeSend = { event in
                continuation.yield(event)
                return nil
            }
        }
        return stream
    }
}
