import Foundation
import Supabase
import Testing
@testable import Howday

struct ErrorHelpersTests {
    /// An `AuthError.api` the way the Supabase SDK hands one back, carrying
    /// only the part these tests turn on: the structured error code.
    private func authError(_ code: ErrorCode, message: String = "") -> AuthError {
        .api(
            message: message,
            errorCode: code,
            underlyingData: Data(),
            underlyingResponse: HTTPURLResponse(
                url: URL(string: "https://example.supabase.co/auth/v1/otp")!,
                statusCode: 422,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    @Test func aNumberTheProviderWontRouteIsTheUsersToFix() {
        // MOODRING-IOS-3: the test number's national half paired with
        // whatever country the picker happened to be sitting on.
        let error = authError(
            .smsSendFailed,
            message: "Error sending confirmation OTP to provider: Invalid parameter `To`: +935005550001"
        )
        #expect(error.isUserCorrectableSignIn)
    }

    @Test func tappingTooFastAndMistypingTheCodeAreTheUsersToFix() {
        #expect(authError(.overSMSSendRateLimit).isUserCorrectableSignIn)
        #expect(authError(.overRequestRateLimit).isUserCorrectableSignIn)
        #expect(authError(.otpExpired).isUserCorrectableSignIn)
        #expect(authError(.validationFailed).isUserCorrectableSignIn)
    }

    @Test func ourOwnConfigurationComingApartIsStillReported() {
        #expect(!authError(.phoneProviderDisabled).isUserCorrectableSignIn)
        #expect(!authError(.otpDisabled).isUserCorrectableSignIn)
        #expect(!authError(.phoneNotConfirmed).isUserCorrectableSignIn)
        #expect(!AuthError.sessionMissing.isUserCorrectableSignIn)
    }

    @Test func errorsThatArentSignInErrorsAreUntouched() {
        #expect(!URLError(.badServerResponse).isUserCorrectableSignIn)
        #expect(!CancellationError().isUserCorrectableSignIn)
    }
}
