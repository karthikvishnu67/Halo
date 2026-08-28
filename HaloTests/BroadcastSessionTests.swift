//
//  BroadcastSessionTests.swift
//  HaloTests
//

import Foundation
import Testing
@testable import Halo

@MainActor
struct BroadcastSessionTests {

    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func aSessionIsActiveUntilItExpires() {
        let session = BroadcastSession(profile: HaloProfile.cast[0],
                                       startedAt: start,
                                       length: .fifteenMinutes)

        #expect(session.isActive(at: start))
        #expect(session.isActive(at: start.addingTimeInterval(14 * 60)))
        #expect(!session.isActive(at: start.addingTimeInterval(15 * 60)),
                "broadcasting must stop on its own; forgetting to turn it off should never mean broadcasting indefinitely")
    }

    @Test func remainingCountsDownAndStopsAtZero() {
        let session = BroadcastSession(profile: HaloProfile.cast[0],
                                       startedAt: start,
                                       length: .oneHour)

        #expect(session.remaining(at: start) == 3600)
        #expect(session.remaining(at: start.addingTimeInterval(600)) == 3000)
        #expect(session.remaining(at: start.addingTimeInterval(7200)) == 0,
                "never reports negative time left")
    }

    @Test func expiryIsNoticedWithoutAnyoneWatchingTheClock() {
        let controller = BroadcastController()
        controller.start(HaloProfile.cast[0], for: .fifteenMinutes, at: start)

        #expect(controller.isBroadcasting(at: start.addingTimeInterval(60)))
        #expect(!controller.isBroadcasting(at: start.addingTimeInterval(16 * 60)))
        #expect(controller.session == nil,
                "an expired session is cleared, so the UI can never show a stale 'you are visible'")
    }

    @Test func stoppingIsImmediate() {
        let controller = BroadcastController()
        controller.start(HaloProfile.cast[0], for: .fourHours, at: start)
        controller.stop()

        #expect(!controller.isBroadcasting(at: start.addingTimeInterval(1)))
    }

    @Test func extendingPushesTheEndOutWithoutRestarting() {
        let controller = BroadcastController()
        controller.start(HaloProfile.cast[0], for: .fifteenMinutes, at: start)
        controller.extend(by: .fifteenMinutes)

        #expect(controller.isBroadcasting(at: start.addingTimeInterval(20 * 60)))
        #expect(!controller.isBroadcasting(at: start.addingTimeInterval(31 * 60)))
    }
}
