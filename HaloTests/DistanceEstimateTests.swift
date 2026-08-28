//
//  DistanceEstimateTests.swift
//  HaloTests
//

import Foundation
import Testing
@testable import Halo

struct DistanceEstimateTests {

    private let fov = 68.0

    /// Place someone at a known distance, compute what fraction of the frame
    /// they would fill, and check the estimate recovers the distance.
    @Test func roundTripAtSeveralDistances() throws {
        for truth in [1.0, 2.0, 3.5, 8.0, 15.0] {
            let fraction = DistanceEstimate.assumedBodySpan
                / (2 * truth * tan(fov / 2 * .pi / 180))
            let recovered = try #require(DistanceEstimate.metres(heightFraction: fraction,
                                                                 fieldOfView: fov))
            #expect(abs(recovered - truth) < 0.01)
        }
    }

    @Test func halfTheApparentSizeReadsTwiceAsFar() throws {
        let near = try #require(DistanceEstimate.metres(heightFraction: 0.4, fieldOfView: fov))
        let far = try #require(DistanceEstimate.metres(heightFraction: 0.2, fieldOfView: fov))
        #expect(abs(far - near * 2) < 0.01)
    }

    @Test func degenerateInputsGiveNoAnswer() {
        #expect(DistanceEstimate.metres(heightFraction: 0, fieldOfView: fov) == nil)
        #expect(DistanceEstimate.metres(heightFraction: 0.3, fieldOfView: 0) == nil)
        #expect(DistanceEstimate.metres(heightFraction: 0.3, fieldOfView: 200) == nil)
    }
}
