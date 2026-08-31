//
//  HaloDraftTests.swift
//  HaloTests
//

import Foundation
import Testing
@testable import Halo

struct HaloDraftTests {

    /// Size is the only limit, and it applies whatever the content is. A
    /// balloon has to stay balloon-sized to stay glanceable in a crowd.
    @Test func longContentIsClippedToBalloonSize() {
        let draft = HaloDraft(name: String(repeating: "a", count: 100),
                              message: String(repeating: "b", count: 300),
                              tintIndex: 0).clamped

        #expect(draft.name.count == HaloDraft.nameLimit)
        #expect(draft.message.count == HaloDraft.messageLimit)
    }

    /// ...and it is a limit on *format*, never on subject. Anything that fits
    /// is allowed through untouched.
    @Test func contentIsNotJudgedOnlyMeasured() {
        let awkward = "don't talk to me 😂 · single · ask about ABBA"
        let draft = HaloDraft(name: "Karthik", message: awkward, tintIndex: 2).clamped

        #expect(draft.message == awkward)
        #expect(draft.profile.message == awkward)
    }

    @Test func anEmptyDraftIsNotBroadcastable() {
        #expect(!HaloDraft().isBroadcastable)
        #expect(!HaloDraft(name: "   ", message: "\n", tintIndex: 0).isBroadcastable,
                "whitespace is still nothing to say")
        #expect(HaloDraft(name: "", message: "free for coffee", tintIndex: 0).isBroadcastable,
                "a message with no name is a perfectly good signal")
    }

    @Test func aStrayTintIndexCannotCrash() {
        #expect(HaloDraft(name: "a", message: "b", tintIndex: 99).clamped.tintIndex
                == HaloDraft.palette.count - 1)
        #expect(HaloDraft(name: "a", message: "b", tintIndex: -5).clamped.tintIndex == 0)
    }

    @Test func surroundingWhitespaceIsDroppedFromWhatIsBroadcast() {
        let profile = HaloDraft(name: "  Karthik  ", message: "  hi  ", tintIndex: 0).profile

        #expect(profile.name == "Karthik")
        #expect(profile.message == "hi")
    }
}
