import Foundation
import Sentry

extension Error {
    /// True when this error just means the surrounding task was cancelled —
    /// e.g. the user switched tabs while a .task-driven load was in flight.
    /// Never worth showing in the UI: the next appearance restarts the load.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    /// PostgREST rejects a freshly refreshed token whose `iat` is a second
    /// or two ahead of its own clock — skew between Supabase's auth and
    /// PostgREST services, nothing on the device. Transient: a retry after
    /// a short pause succeeds.
    var isJWTClockSkew: Bool {
        localizedDescription.localizedCaseInsensitiveContains("issued at future")
    }

    /// The device couldn't reach the network — backgrounded mid-request, no
    /// signal, DNS or the connection dropped. Worth showing the user (the load
    /// really did fail) but never worth a Sentry issue: there is no defect to
    /// find, and one issue per blip is how a project fills with noise. The
    /// board load is the usual source, cut off with ECONNRESET when the app
    /// goes to the background mid-request.
    var isTransientNetwork: Bool {
        let nsError = self as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorInternationalRoamingOff,
            NSURLErrorCallIsActive,
            NSURLErrorDataNotAllowed,
        ].contains(nsError.code)
    }

    /// Sends the error to Sentry (no-op in Debug, where the SDK isn't
    /// started) and returns the text to show the user. Cancellations and
    /// transient network failures are never reported, but their text is still
    /// returned: what the user sees and what Sentry keeps are separate calls.
    @discardableResult
    func report(_ flow: String) -> String {
        if !isCancellation && !isTransientNetwork {
            SentrySDK.capture(error: self) { scope in
                scope.setTag(value: flow, key: "flow")
            }
        }
        return localizedDescription
    }
}

/// Runs `operation`, retrying once after a short pause if it fails with the
/// transient PostgREST clock-skew error (see `isJWTClockSkew`).
func withSkewRetry<T>(_ operation: () async throws -> T) async throws -> T {
    do {
        return try await operation()
    } catch where error.isJWTClockSkew {
        try await Task.sleep(for: .seconds(2))
        return try await operation()
    }
}
