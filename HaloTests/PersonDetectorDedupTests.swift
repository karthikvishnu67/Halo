//
//  PersonDetectorDedupTests.swift
//  HaloTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Halo

@MainActor
struct PersonDetectorDedupTests {

    private func det(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     confidence: Float) -> DetectedPerson {
        DetectedPerson(id: UUID(),
                       boundingBox: CGRect(x: x, y: y, width: w, height: h),
                       headPoint: CGPoint(x: x + w / 2, y: y),
                       confidence: confidence)
    }

    /// The exact pair of boxes Vision returned for one seated person, captured
    /// from a real frame. Their IoU is 0.284 — under the tracker's matching
    /// threshold — which is why plain IoU couldn't catch the duplicate.
    @Test func nestedDuplicateFromRealFrameIsDropped() {
        let detector = PersonDetector()
        let boxes = [det(0.136, 0.134, 0.795, 0.469, confidence: 0.63),
                     det(0.144, 0.370, 0.475, 0.223, confidence: 0.56)]
        let kept = detector.suppressDuplicates(boxes)
        #expect(kept.count == 1)
        #expect(kept.first?.confidence == 0.63, "the higher-confidence box should win")
    }

    @Test func separatePeopleAreBothKept() {
        let detector = PersonDetector()
        let boxes = [det(0.10, 0.30, 0.15, 0.50, confidence: 0.9),
                     det(0.60, 0.30, 0.15, 0.50, confidence: 0.8)]
        #expect(detector.suppressDuplicates(boxes).count == 2)
    }

    /// People shoulder to shoulder overlap somewhat; both must survive.
    @Test func adjacentPeopleAreBothKept() {
        let detector = PersonDetector()
        let boxes = [det(0.30, 0.30, 0.18, 0.50, confidence: 0.9),
                     det(0.42, 0.30, 0.18, 0.50, confidence: 0.8)]
        #expect(detector.suppressDuplicates(boxes).count == 2)
    }
}
