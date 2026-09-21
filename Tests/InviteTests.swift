import Foundation
import Testing
@testable import Howday

/// The invite is copy, so the copy is what's tested. The contacts sentence
/// in particular: without it a recipient installs, lands on an empty board
/// and has no way to find the person who invited them.
struct InviteTests {
    @Test func theMessageTellsTheRecipientToSaveTheNumber() {
        #expect(Invite.message.localizedCaseInsensitiveContains("contacts"))
    }

    /// The one thing a share target can't do without: Copy hands over
    /// exactly this string, so the link has to be inside it.
    @Test func theSharedTextCarriesTheLink() {
        let text = Invite.shareText(url: URL(string: "https://example.com/get")!)
        #expect(text.contains("https://example.com/get"))
        #expect(text.hasPrefix(Invite.message))
    }

    @Test func theContactsSummaryAgreesWithItsNumber() {
        #expect(Invite.contactsSummary(count: 0) == "None of your contacts are on Howday yet")
        #expect(Invite.contactsSummary(count: 1) == "1 of your contacts is on Howday")
        #expect(Invite.contactsSummary(count: 3) == "3 of your contacts are on Howday")
    }
}
