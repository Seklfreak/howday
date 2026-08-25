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

    /// Sends the error to Sentry (no-op in Debug, where the SDK isn't
    /// started) and returns the text to show the user. Cancellations are
    /// never reported — callers should already have filtered them out.
    @discardableResult
    func report(_ flow: String) -> String {
        if !isCancellation {
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
