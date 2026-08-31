//
//  PersonTrackerTests.swift
//  HaloTests
//
//  The tracker is pure logic, so everything here runs without a camera.
//

import CoreGraphics
import Foundation
import Testing
@testable import Halo

@MainActor
struct PersonTrackerTests {

    /// Detection runs at roughly this rate.
    private let pass: TimeInterval = 1.0 / 15

    /// A fake detection at a given normalized box, head at the box's top centre.
    private func det(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> DetectedPerson {
        DetectedPerson(id: UUID(),
                       boundingBox: CGRect(x: x, y: y, width: w, height: h),
                       headPoint: CGPoint(x: x + w / 2, y: y),
                       confidence: 0.9)
    }

    // MARK: identity

    @Test func walkingPersonKeepsASingleID() {
        let tracker = PersonTracker()
        var ids: Set<Int> = []
        for step in 0..<10 {
            let x = 0.20 + CGFloat(step) * 0.02
            ids.insert(tracker.update(with: [det(x, 0.3, 0.15, 0.5)],
                                      at: Double(step) * pass)[0].id)
        }
        #expect(ids.count == 1, "one person walking should stay one subject")
    }

    @Test func idSurvivesABriefDetectionDropout() {
        let tracker = PersonTracker()
        let before = tracker.update(with: [det(0.3, 0.3, 0.15, 0.5)], at: 0)[0].id
        for step in 1...3 { _ = tracker.update(with: [], at: Double(step) * pass) }
        let after = tracker.update(with: [det(0.31, 0.3, 0.15, 0.5)], at: 4 * pass)[0].id
        #expect(before == after, "a 3-pass dropout must not create a new subject")
    }

    @Test func aLongAbsenceRetiresTheTrack() {
        let tracker = PersonTracker()
        let old = tracker.update(with: [det(0.3, 0.3, 0.15, 0.5)], at: 0)[0].id
        _ = tracker.update(with: [], at: 4)
        let fresh = tracker.update(with: [det(0.3, 0.3, 0.15, 0.5)], at: 4.1)[0].id
        #expect(old != fresh, "identity must not survive leaving the frame — by design")
    }

    @Test func twoPeopleKeepTwoStableIDs() {
        let tracker = PersonTracker()
        var idPairs: Set<String> = []
        for step in 0..<6 {
            let d = CGFloat(step) * 0.01
            let people = tracker.update(with: [det(0.15 + d, 0.3, 0.12, 0.5),
                                               det(0.60 - d, 0.3, 0.12, 0.5)],
                                        at: Double(step) * pass)
            idPairs.insert("\(people.map(\.id).sorted())")
        }
        #expect(idPairs.count == 1, "two people should keep the same two ids throughout")
    }

    @Test func ghostBoxDisappearsQuickly() {
        let tracker = PersonTracker()
        _ = tracker.update(with: [det(0.3, 0.3, 0.15, 0.5)], at: 0)

        #expect(tracker.update(with: [], at: 0.3).count == 1,
                "a momentary dropout must not blink a halo off someone still standing there")
        #expect(tracker.update(with: [], at: 1.2).count == 0,
                "but someone who has actually gone must not leave one hanging in the air")
    }

    /// The failure seen on device: moving the camera shifts every box at once,
    /// so a person plainly still in frame was becoming a brand new subject —
    /// which cost them their identity and handed them somebody else's halo.
    @Test func aPersonSurvivesTheCameraBeingMoved() {
        let tracker = PersonTracker()
        let before = tracker.update(with: [det(0.30, 0.30, 0.15, 0.50)], at: 0)[0].id

        // A sharp pan: the same person, now a full box-width to the left, with
        // no overlap at all between where they were and where they now are.
        let after = tracker.update(with: [det(0.14, 0.31, 0.15, 0.50)], at: pass)

        #expect(after.count == 1, "one person, not two")
        #expect(after.first?.id == before, "and still the same person")
    }

    /// That tolerance must not stretch so far that distinct people merge.
    @Test func someoneAcrossTheFrameIsADifferentPerson() {
        let tracker = PersonTracker()
        let near = tracker.update(with: [det(0.08, 0.30, 0.12, 0.50)], at: 0)[0].id
        let people = tracker.update(with: [det(0.78, 0.30, 0.12, 0.50)], at: pass)

        // The original is still drawn for a moment — a dropout must not blink
        // someone off — so look for whoever is at the new position.
        let acrossTheFrame = people.first { $0.boundingBox.midX > 0.6 }
        #expect(acrossTheFrame != nil, "the new detection should be tracked")
        #expect(acrossTheFrame?.id != near, "and must not have stolen the other person's identity")
    }

    /// Coming back after a short loss of sight keeps the same identity, so the
    /// halo returns as the same halo rather than a stranger's.
    @Test func returningAfterABriefGapKeepsIdentity() {
        let tracker = PersonTracker()
        let before = tracker.update(with: [det(0.30, 0.30, 0.15, 0.50)], at: 0)[0].id
        for step in 1...15 { _ = tracker.update(with: [], at: Double(step) * pass) }
        let after = tracker.update(with: [det(0.32, 0.30, 0.15, 0.50)], at: 1.1)

        #expect(after.first?.id == before, "a second out of sight is not a new person")
    }

    // MARK: smoothing

    /// The detector shivering by ±0.01 on a stationary person must be mostly
    /// filtered out, or the halo twitches.
    @Test func stationaryJitterIsSuppressed() {
        let tracker = PersonTracker()
        var lo: CGFloat = 1, hi: CGFloat = 0
        for step in 0..<60 {
            let jitter: CGFloat = step % 2 == 0 ? 0.01 : -0.01
            let person = tracker.update(with: [det(0.30 + jitter, 0.30, 0.15, 0.50)],
                                        at: Double(step) * pass)[0]
            if step > 25 {
                lo = min(lo, person.displayHead.x)
                hi = max(hi, person.displayHead.x)
            }
        }
        #expect(hi - lo < 0.004,
                "raw input spread is 0.02; the displayed spread must be far smaller")
    }

    /// Filtering must not leave the halo trailing behind a walking person.
    @Test func walkerLagStaysSmall() {
        let tracker = PersonTracker()
        var lag: CGFloat = 0
        for step in 0..<40 {
            let x = 0.10 + CGFloat(step) * 0.02
            let person = tracker.update(with: [det(x, 0.3, 0.15, 0.5)], at: Double(step) * pass)[0]
            if step > 25 { lag = abs(person.boundingBox.midX - person.displayHead.x) }
        }
        #expect(lag < 0.015, "the halo should track a brisk walker closely")
    }

    /// Small genuine movement — shifting in a chair — must still be followed.
    @Test func slowMovementIsStillFollowed() {
        let tracker = PersonTracker()
        var lag: CGFloat = 0
        for step in 0..<40 {
            let x = 0.30 + CGFloat(step) * 0.004
            let person = tracker.update(with: [det(x, 0.3, 0.15, 0.5)], at: Double(step) * pass)[0]
            if step > 25 { lag = abs(person.boundingBox.midX - person.displayHead.x) }
        }
        #expect(lag < 0.02, "heavy stationary filtering must not freeze slow drift")
    }
}
