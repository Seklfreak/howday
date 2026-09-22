import Foundation
import Sentry
import Supabase

extension Error {
    /// Sign-in failures the person holding the phone can fix themselves: a
    /// number the provider won't route, a code typed wrong, a second tap
    /// that came too soon. `PhoneSignInView.friendlyMessage` already puts
    /// every one of these on screen in words they can act on — filing them
    /// as issues as well claims the app is broken while it is doing exactly
    /// what it should. Reporting and showing are separate calls; only the
    /// reporting stops here.
    ///
    /// The one that filled the project was `smsSendFailed`: the sign-in
    /// notes give the Supabase test number as `+1 500 555 0001`, testers
    /// type the `500 555 0001` half while the picker still sits on their own
    /// region (`CountryCode.deviceDefault`), and Twilio refuses the
    /// `+93…`/`+213…`/`+355…` that comes out with a 60200.
    ///
    /// Codes deliberately absent stay reported: `phoneProviderDisabled`,
    /// `otpDisabled`, `phoneNotConfirmed` and the rest are our own
    /// configuration coming apart, and nobody at the keyboard can fix those.
    var isUserCorrectableSignIn: Bool {
        guard let authError = self as? AuthError else { return false }
        return [
            // Provider refused the number — wrong country in the picker, or
            // digits that aren't a phone number anywhere.
            ErrorCode.smsSendFailed,
            // "Send code"/"Resend" tapped faster than the provider allows.
            .overSMSSendRateLimit,
            .overRequestRateLimit,
            // gotrue answers a *wrong* code with this as well as a stale
            // one, so it is mistyping as much as expiry. A real verification
            // outage would hide behind it — the `signin_code_sent` →
            // `signin_completed` pair is what measures that, which is why
            // those two events are tracked where they are.
            .otpExpired,
            // Malformed input, rejected before the provider was asked.
            .validationFailed,
        ].contains(authError.errorCode)
    }

    /// Sends the error to Sentry (no-op in Debug, where the SDK isn't
    /// started) and returns the text to show the user. Cancellations,
    /// transient network failures and sign-in mistakes are never reported,
    /// but their text is still returned: what the user sees and what Sentry
    /// keeps are separate calls.
    @discardableResult
    func report(_ flow: String) -> String {
        if !isCancellation && !isTransientNetwork && !isUserCorrectableSignIn {
            SentrySDK.capture(error: self) { scope in
                scope.setTag(value: flow, key: "flow")
            }
        }
        return localizedDescription
    }
}
