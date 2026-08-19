import Foundation

extension Error {
    /// True when this error just means the surrounding task was cancelled —
    /// e.g. the user switched tabs while a .task-driven load was in flight.
    /// Never worth showing in the UI: the next appearance restarts the load.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
