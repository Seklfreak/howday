import Foundation
import Sentry

extension Error {
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
