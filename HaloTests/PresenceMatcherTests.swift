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

@MainActor
struct PresenceMatcherTests {

    private func presence(_ id: String, _ distance: Double) -> HaloPresence {
        HaloPresence(id: id, profile: HaloProfile.cast[0], estimatedDistance: distance)
    }

    /// Radio distance is poor: several metres of error, biased long because
    /// bodies absorb the signal.
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

        // Body 1 is the owner of "aaa" at 2m; body 2 owns "bbb" at 9m.
        for _ in 0..<40 {
            outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(2, &rng)),
                           .init(id: 2, distance: seen(9, &rng))],
                presences: [presence("aaa", heard(2, &rng)),
                            presence("bbb", heard(9, &rng))])
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

        for _ in 0..<40 {
            outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(4, &rng)),
                           .init(id: 2, distance: seen(4, &rng))],
                presences: [presence("aaa", heard(4, &rng))])
        }

        #expect(outcome!.matched.isEmpty, "ambiguity must produce no placement at all")
        #expect(outcome!.unplaced.count == 1, "the broadcast is still heard, just unplaced")
    }

    /// ...and when one of them walks away, the ambiguity resolves itself.
    @Test func divergingPathsResolveAmbiguity() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 3)
        var outcome: PresenceMatcher.Outcome?

        // Both start at 4m. Body 2 — who owns the broadcast — walks away.
        for step in 0..<50 {
            let walker = 4.0 + Double(step) * 0.14
            outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(4, &rng)),
                           .init(id: 2, distance: seen(walker, &rng))],
                presences: [presence("aaa", heard(walker, &rng))])
        }

        #expect(outcome!.matched.count == 1)
        #expect(outcome!.matched.first?.trackID == 2,
                "the broadcast whose distance grew with body 2 belongs to body 2")
    }

    // MARK: it stays quiet when it should

    @Test func aBroadcastWithNoVisibleBodyStaysUnplaced() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 4)
        var outcome: PresenceMatcher.Outcome?

        // Someone broadcasting from behind you, or through a wall: heard at
        // 6m, but the only visible person is right in front of you.
        for _ in 0..<40 {
            outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(1.5, &rng))],
                presences: [presence("aaa", heard(6, &rng))])
        }

        #expect(outcome!.matched.isEmpty)
        #expect(outcome!.unplaced.count == 1)
    }

    @Test func peopleWithoutHalosNeverGetOne() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 5)
        var outcome: PresenceMatcher.Outcome?

        // Three people in view, one broadcast, belonging to the middle one.
        for _ in 0..<40 {
            outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(1.5, &rng)),
                           .init(id: 2, distance: seen(6, &rng)),
                           .init(id: 3, distance: seen(12, &rng))],
                presences: [presence("aaa", heard(6, &rng))])
        }

        #expect(outcome!.matched.count == 1, "exactly one person may receive it")
        #expect(outcome!.matched.first?.trackID == 2)
    }

    @Test func subjectsWithNoDistanceEstimateAreNotGuessedAt() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 6)
        var outcome: PresenceMatcher.Outcome?

        // A seated person whose apparent size tells us nothing.
        for _ in 0..<30 {
            outcome = matcher.update(
                subjects: [.init(id: 1, distance: nil)],
                presences: [presence("aaa", heard(3, &rng))])
        }

        #expect(outcome!.matched.isEmpty)
    }

    // MARK: stability

    /// Once settled, a placement should ride out a patch of bad signal rather
    /// than blinking off the person it has already committed to.
    @Test func aSettledPlacementSurvivesNoisySignal() {
        let matcher = PresenceMatcher()
        var rng = SeededGenerator(seed: 7)

        for _ in 0..<40 {
            _ = matcher.update(subjects: [.init(id: 1, distance: seen(3, &rng)),
                                          .init(id: 2, distance: seen(11, &rng))],
                               presences: [presence("aaa", heard(3, &rng))])
        }

        // Several passes where the radio reads badly long.
        var held = true
        for _ in 0..<6 {
            let outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(3, &rng)),
                           .init(id: 2, distance: seen(11, &rng))],
                presences: [presence("aaa", 6.5)])
            if outcome.matched.first?.trackID != 1 { held = false }
        }

        #expect(held, "a few bad readings must not detach a settled halo")
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
        var correctPasses = 0

        // Body 1 owns "aaa" and body 2 owns "bbb". They cross paths: 1 walks
        // out from 2m to 12m while 2 walks in from 12m to 2m, so they pass
        // through the same distance at the midpoint.
        for step in 0..<80 {
            let progress = Double(step) / 79
            let first = 2 + 10 * progress
            let second = 12 - 10 * progress

            let outcome = matcher.update(
                subjects: [.init(id: 1, distance: seen(first, &rng)),
                           .init(id: 2, distance: seen(second, &rng))],
                presences: [presence("aaa", heard(first, &rng)),
                            presence("bbb", heard(second, &rng))])

            for match in outcome.matched {
                let expected = match.presence.id == "aaa" ? 1 : 2
                if match.trackID != expected { wrongPlacements += 1 }
            }
            if outcome.matched.count == 2 { correctPasses += 1 }
        }

        #expect(wrongPlacements == 0, "never put a signal above the wrong head")
        #expect(correctPasses > 20, "it should still manage to place them most of the time")
    }
}
