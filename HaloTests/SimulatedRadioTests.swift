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
        // The simulator's broadcasters follow the nearest person and the third
        // nearest, so the middle one is deliberately not a Halo user.
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

    /// A broadcast must not change identity just because the camera lost sight
    /// of its owner for a moment and gave them a new track id. On device that
    /// turned one person into a succession of different strangers.
    @Test func aBroadcastKeepsItsIdentityWhenTrackIDsChange() {
        let radio = SimulatedRadio(seed: 3)

        let before = radio.presences(for: [.init(id: 7, distance: 2.5)], at: 0)
        // Same person, same place, new track id — the camera blinked.
        let after = radio.presences(for: [.init(id: 41, distance: 2.5)], at: 2)

        #expect(before.first?.id == after.first?.id, "the same broadcast, still")
        #expect(before.first?.profile.name == after.first?.profile.name,
                "and still the same person's halo")
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
