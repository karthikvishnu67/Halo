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
            ids.insert(tracker.update(with: [det(x, 0.3, 0.15, 0.5)])[0].id)
        }
        #expect(ids.count == 1, "one person walking should stay one subject")
    }

    @Test func idSurvivesABriefDetectionDropout() {
        let tracker = PersonTracker()
        let before = tracker.update(with: [det(0.3, 0.3, 0.15, 0.5)])[0].id
        for _ in 0..<3 { _ = tracker.update(with: []) }
        let after = tracker.update(with: [det(0.31, 0.3, 0.15, 0.5)])[0].id
        #expect(before == after, "a 3-pass dropout must not create a new subject")
    }

    @Test func aLongAbsenceRetiresTheTrack() {
        let tracker = PersonTracker()
        let old = tracker.update(with: [det(0.3, 0.3, 0.15, 0.5)])[0].id
        for _ in 0..<12 { _ = tracker.update(with: []) }
        let fresh = tracker.update(with: [det(0.3, 0.3, 0.15, 0.5)])[0].id
        #expect(old != fresh, "identity must not survive leaving the frame — by design")
    }

    @Test func twoPeopleKeepTwoStableIDs() {
        let tracker = PersonTracker()
        var idPairs: Set<String> = []
        for step in 0..<6 {
            let d = CGFloat(step) * 0.01
            let people = tracker.update(with: [det(0.15 + d, 0.3, 0.12, 0.5),
                                               det(0.60 - d, 0.3, 0.12, 0.5)])
            idPairs.insert("\(people.map(\.id).sorted())")
        }
        #expect(idPairs.count == 1, "two people should keep the same two ids throughout")
    }

    @Test func ghostBoxDisappearsQuickly() {
        let tracker = PersonTracker()
        _ = tracker.update(with: [det(0.3, 0.3, 0.15, 0.5)])
        var visible: [Int] = []
        for _ in 0..<5 { visible.append(tracker.update(with: []).count) }
        #expect(visible == [1, 1, 0, 0, 0],
                "a departed subject may linger briefly but must not hang in space")
    }

    // MARK: smoothing

    /// The detector shivering by ±0.01 on a stationary person must be mostly
    /// filtered out, or the halo twitches.
    @Test func stationaryJitterIsSuppressed() {
        let tracker = PersonTracker()
        var lo: CGFloat = 1, hi: CGFloat = 0
        for step in 0..<60 {
            let jitter: CGFloat = step % 2 == 0 ? 0.01 : -0.01
            let person = tracker.update(with: [det(0.30 + jitter, 0.30, 0.15, 0.50)])[0]
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
            let person = tracker.update(with: [det(x, 0.3, 0.15, 0.5)])[0]
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
            let person = tracker.update(with: [det(x, 0.3, 0.15, 0.5)])[0]
            if step > 25 { lag = abs(person.boundingBox.midX - person.displayHead.x) }
        }
        #expect(lag < 0.02, "heavy stationary filtering must not freeze slow drift")
    }
}
