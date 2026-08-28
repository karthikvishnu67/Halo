//
//  PresenceMatcherTests.swift
//  HaloTests
//
//  Simulated radio: ground truth is known, so we can check not only that the
//  matcher gets it right, but that it stays silent when it cannot know.
//

import Foundation
import Testing
@testable import Halo

/// Seeded so a failure is always reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

/// The camera runs at roughly this rate, and the matcher is driven from it.
private let cameraInterval: TimeInterval = 1.0 / 15

@MainActor
struct PresenceMatcherTests {

    private func presence(_ id: String, _ distance: Double, heardAt: TimeInterval) -> HaloPresence {
        HaloPresence(id: id, profile: HaloProfile.cast[0],
                     rawDistance: distance, heardAt: heardAt)
    }

    /// Radio distance is poor, and biased long: obstruction weakens a signal,
    /// which reads as further away.
    private func heard(_ trueDistance: Double, _ rng: inout SeededGenerator) -> Double {
        max(0.3, trueDistance + Double.random(in: -1.5...2.5, using: &rng))
    }

    /// Camera distance is decent but not exact.
    private func seen(_ trueDistance: Double, _ rng: inout SeededGenerator) -> Double {
        max(0.3, trueDistance + Double.random(in: -0.25...0.25, using: &rng))
    }

    // MARK: it places what it can

    @Test func twoPeopleAtDifferentDistancesArePlacedCorrectly() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 1)
        var outcome: PresenceMatcher.Outcome?

        for step in 0..<60 {
            let now = Double(step) * cameraInterval
            outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(2, &rng)),
                           .init(id: 2, distance: seen(9, &rng))],
                presences: [presence("aaa", heard(2, &rng), heardAt: now),
                            presence("bbb", heard(9, &rng), heardAt: now)],
                now: now)
        }

        let matched = Dictionary(uniqueKeysWithValues:
            outcome!.matched.map { ($0.presence.id, $0.trackID) })
        #expect(matched["aaa"] == 1)
        #expect(matched["bbb"] == 2)
        #expect(outcome!.unplaced.isEmpty)
    }

    /// The whole point: two people the same distance away, nobody moving, is
    /// genuinely unanswerable — so the matcher must say nothing rather than
    /// put someone's message over a stranger's head.
    @Test func identicalDistancesRefuseToBind() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 2)
        var outcome: PresenceMatcher.Outcome?

        for step in 0..<60 {
            let now = Double(step) * cameraInterval
            outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(4, &rng)),
                           .init(id: 2, distance: seen(4, &rng))],
                presences: [presence("aaa", heard(4, &rng), heardAt: now)],
                now: now)
        }

        #expect(outcome!.matched.isEmpty, "ambiguity must produce no placement at all")
        #expect(outcome!.unplaced.count == 1, "the broadcast is still heard, just unplaced")
    }

    /// ...and when one of them walks away, the ambiguity resolves itself.
    @Test func divergingPathsResolveAmbiguity() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 3)
        var outcome: PresenceMatcher.Outcome?

        // Both start at 4m. Body 2 — who owns the broadcast — walks away at
        // roughly a metre a second.
        for step in 0..<120 {
            let now = Double(step) * cameraInterval
            let walker = 4.0 + now * 1.0
            outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(4, &rng)),
                           .init(id: 2, distance: seen(walker, &rng))],
                presences: [presence("aaa", heard(walker, &rng), heardAt: now)],
                now: now)
        }

        #expect(outcome!.matched.count == 1)
        #expect(outcome!.matched.first?.trackID == 2,
                "the broadcast whose distance grew with body 2 belongs to body 2")
    }

    /// iOS slows advertising down when an app is backgrounded, so a phone in
    /// someone's pocket may only be heard about once a second while the camera
    /// runs fifteen times faster. The matcher must still place them.
    @Test func aBackgroundedBroadcasterIsStillPlaced() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 11)
        var outcome: PresenceMatcher.Outcome?
        var lastHeard: TimeInterval = 0
        var lastReading = 3.0

        for step in 0..<200 {
            let now = Double(step) * cameraInterval

            // A new radio reading only about once a second.
            if now - lastHeard >= 1.0 {
                lastHeard = now
                lastReading = heard(3, &rng)
            }

            outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(3, &rng)),
                           .init(id: 2, distance: seen(12, &rng))],
                presences: [presence("aaa", lastReading, heardAt: lastHeard)],
                now: now)
        }

        #expect(outcome!.matched.first?.trackID == 1,
                "a once-a-second broadcast should still find its owner")
    }

    // MARK: it stays quiet when it should

    @Test func aBroadcastWithNoVisibleBodyStaysUnplaced() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 4)
        var outcome: PresenceMatcher.Outcome?

        // Someone broadcasting from behind you, or through a wall: heard at
        // 6m, but the only visible person is right in front of you.
        for step in 0..<60 {
            let now = Double(step) * cameraInterval
            outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(1.5, &rng))],
                presences: [presence("aaa", heard(6, &rng), heardAt: now)],
                now: now)
        }

        #expect(outcome!.matched.isEmpty)
        #expect(outcome!.unplaced.count == 1)
    }

    @Test func peopleWithoutHalosNeverGetOne() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 5)
        var outcome: PresenceMatcher.Outcome?

        // Three people in view, one broadcast, belonging to the middle one.
        for step in 0..<60 {
            let now = Double(step) * cameraInterval
            outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(1.5, &rng)),
                           .init(id: 2, distance: seen(6, &rng)),
                           .init(id: 3, distance: seen(12, &rng))],
                presences: [presence("aaa", heard(6, &rng), heardAt: now)],
                now: now)
        }

        #expect(outcome!.matched.count == 1, "exactly one person may receive it")
        #expect(outcome!.matched.first?.trackID == 2)
    }

    @Test func subjectsWithNoDistanceEstimateAreNotGuessedAt() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 6)
        var outcome: PresenceMatcher.Outcome?

        // A seated person whose apparent size tells us nothing.
        for step in 0..<45 {
            let now = Double(step) * cameraInterval
            outcome = matcher.update(
                subjects: [.init(id: 1, distance: nil)],
                presences: [presence("aaa", heard(3, &rng), heardAt: now)],
                now: now)
        }

        #expect(outcome!.matched.isEmpty)
    }

    /// iOS offers no way to keep advertising through a force-quit, so a
    /// broadcast simply stopping is ordinary rather than exceptional. The halo
    /// must disappear rather than hang above someone indefinitely.
    @Test func aBroadcastThatStopsDisappears() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 12)

        var settled: PresenceMatcher.Outcome?
        for step in 0..<60 {
            let now = Double(step) * cameraInterval
            settled = matcher.update(
                subjects: [.init(id: 1, distance: seen(3, &rng))],
                presences: [presence("aaa", heard(3, &rng), heardAt: now)],
                now: now)
        }
        #expect(settled!.matched.count == 1, "should be placed before the app is killed")

        // The phone stops advertising: the last reading never gets newer.
        let killedAt = 60 * cameraInterval
        var after: PresenceMatcher.Outcome?
        for step in 60..<180 {
            let now = Double(step) * cameraInterval
            after = matcher.update(
                subjects: [.init(id: 1, distance: seen(3, &rng))],
                presences: [presence("aaa", 3.0, heardAt: killedAt)],
                now: now)
        }

        #expect(after!.matched.isEmpty, "a halo must not outlive the broadcast")
        #expect(after!.unplaced.isEmpty, "nor should it linger as an ambient count")
    }

    // MARK: stability

    /// Once settled, a placement should ride out a patch of bad signal rather
    /// than blinking off the person it has already committed to.
    @Test func aSettledPlacementSurvivesNoisySignal() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 7)
        var step = 0

        func advance() -> TimeInterval {
            defer { step += 1 }
            return Double(step) * cameraInterval
        }

        for _ in 0..<60 {
            let now = advance()
            _ = matcher.update(subjects: [.init(id: 1, distance: seen(3, &rng)),
                                          .init(id: 2, distance: seen(11, &rng))],
                               presences: [presence("aaa", heard(3, &rng), heardAt: now)],
                               now: now)
        }

        // Several seconds where the radio reads badly long.
        var held = true
        for _ in 0..<30 {
            let now = advance()
            let outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(3, &rng)),
                           .init(id: 2, distance: seen(11, &rng))],
                presences: [presence("aaa", 6.5, heardAt: now)],
                now: now)
            if outcome.matched.first?.trackID != 1 { held = false }
        }

        #expect(held, "a stretch of bad readings must not detach a settled halo")
    }

    /// The safety property, stated directly: across a long run with people
    /// moving around each other, the matcher must never once place a broadcast
    /// on the wrong person. Silence is always an acceptable answer.
    ///
    /// Run over many seeds deliberately. A single seed passed while others
    /// failed when this was first written — near the crossing point the radio
    /// reports the two people in the *wrong order* for seconds at a time, so
    /// one lucky noise sequence proves nothing.
    @Test(arguments: 1...60 as ClosedRange<UInt64>)
    func neverPlacesABroadcastOnTheWrongPerson(seed: UInt64) {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: seed)
        var wrongPlacements = 0
        var correctPlacements = 0

        // Body 1 owns "aaa" and body 2 owns "bbb". They cross paths: 1 walks
        // out from 2m to 12m while 2 walks in from 12m to 2m, so they pass
        // through the same distance at the midpoint.
        for step in 0..<120 {
            let now = Double(step) * cameraInterval
            let progress = Double(step) / 119
            let first = 2 + 10 * progress
            let second = 12 - 10 * progress

            let outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(first, &rng)),
                           .init(id: 2, distance: seen(second, &rng))],
                presences: [presence("aaa", heard(first, &rng), heardAt: now),
                            presence("bbb", heard(second, &rng), heardAt: now)],
                now: now)

            for match in outcome.matched {
                let expected = match.presence.id == "aaa" ? 1 : 2
                if match.trackID == expected { correctPlacements += 1 } else { wrongPlacements += 1 }
            }
        }

        #expect(wrongPlacements == 0, "never put a signal above the wrong head")

        // Silence must not be how this test passes. But note what is *not*
        // asserted: that both people are placed throughout. For most of this
        // scenario they are within 3.5m of each other, which is inside the
        // radio's own noise, and placing both confidently there would be
        // claiming certainty the evidence does not support. Placing one and
        // abstaining on the other is the correct behaviour, not a shortfall.
        #expect(correctPlacements > 30, "it must still be actively placing, not merely mute")
    }
}
