//
//  SimulatedRadioTests.swift
//  HaloTests
//
//  The whole V2 chain, end to end, with no Bluetooth and no camera: broadcasts
//  heard, distances de-biased, matched to bodies, halos placed.
//

import Foundation
import Testing
@testable import Halo

@MainActor
struct SimulatedRadioTests {

    private let cameraInterval: TimeInterval = 1.0 / 15

    /// Drives radio and matcher together for a few seconds and reports who
    /// ended up with a halo.
    private func run(subjects: [PresenceMatcher.Subject],
                     seconds: Double = 8,
                     seed: UInt64) -> PresenceMatcher.Outcome {
        let radio = SimulatedRadio(seed: seed)
        let matcher = PresenceMatcher()
        var outcome = PresenceMatcher.Outcome(matched: [], unplaced: [])

        for step in 0..<Int(seconds / cameraInterval) {
            let now = Double(step) * cameraInterval
            outcome = matcher.update(subjects: subjects,
                                     presences: radio.presences(for: subjects, at: now),
                                     now: now)
        }
        return outcome
    }

    /// The point of the whole design: people who aren't broadcasting get
    /// nothing. Not a marker, not a placeholder — absent.
    @Test(arguments: 1...20 as ClosedRange<UInt64>)
    func onlyBroadcastersGetHalos(seed: UInt64) {
        // The simulator treats odd track ids as Halo users.
        let subjects: [PresenceMatcher.Subject] = [
            .init(id: 1, distance: 2.0),
            .init(id: 2, distance: 6.0),
            .init(id: 3, distance: 10.0),
        ]

        let placed = Set(run(subjects: subjects, seed: seed).matched.map(\.trackID))

        #expect(!placed.contains(2), "someone who never opted in must never be given a halo")
        #expect(placed.contains(1) || placed.contains(3),
                "at least one real broadcaster should be found")
    }

    /// A broadcast from outside the camera's view — behind you, or through a
    /// wall — must be reported as heard, and never hung on somebody visible.
    @Test(arguments: 1...20 as ClosedRange<UInt64>)
    func anUnseenBroadcasterIsNeverPlacedOnAnyone(seed: UInt64) {
        let subjects: [PresenceMatcher.Subject] = [
            .init(id: 1, distance: 2.0),
            .init(id: 2, distance: 5.0),
        ]

        let outcome = run(subjects: subjects, seed: seed)
        let placedIDs = Set(outcome.matched.map(\.presence.id))

        #expect(!placedIDs.contains("sim-unseen"),
                "a broadcast with no matching body must stay unplaced")
        #expect(outcome.unplaced.contains { $0.id == "sim-unseen" },
                "but it should still be heard, for the ambient count")
    }

    /// Nobody visible at all: everything heard stays ambient.
    @Test func withNobodyInFrameNothingIsPlaced() {
        let outcome = run(subjects: [], seed: 42)

        #expect(outcome.matched.isEmpty)
        #expect(outcome.unplaced.count == 1, "the unseen broadcaster is still audible")
    }

    /// The simulator must reproduce exactly when seeded, or a failing run can't
    /// be investigated.
    @Test func aSeededRunRepeatsExactly() {
        let subjects: [PresenceMatcher.Subject] = [.init(id: 1, distance: 3)]

        let first = run(subjects: subjects, seed: 7).matched.map(\.trackID)
        let second = run(subjects: subjects, seed: 7).matched.map(\.trackID)

        #expect(first == second)
    }
}
