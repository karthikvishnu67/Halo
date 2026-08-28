//
//  RadioDistanceFilterTests.swift
//  HaloTests
//

import Foundation
import Testing
@testable import Halo

struct RadioDistanceFilterTests {

    /// Someone standing 3m away with their phone in a front pocket: most
    /// readings are inflated by their own body, a few get through cleanly.
    /// Averaging would report them far away; the filter should not.
    @Test func obstructionBiasIsRejected() throws {
        var filter = RadioDistanceFilter()
        let readings = [3.1, 6.4, 7.0, 3.0, 5.9, 6.8, 3.2, 7.4]
        for (index, reading) in readings.enumerated() {
            filter.add(reading, at: Double(index) * 0.3)
        }

        let mean = readings.reduce(0, +) / Double(readings.count)
        let estimate = try #require(filter.estimate(at: 2.1))

        #expect(abs(estimate - 3.0) < 0.6, "should land near the unobstructed truth of 3m")
        #expect(estimate < mean - 1.5, "and well below the average, which the blocked readings drag out")
    }

    /// The same trick must not distort someone who is simply walking. Their
    /// distance genuinely changes across the window, and older readings are
    /// carried forward rather than treated as interference.
    @Test func movementIsNotMistakenForInterference() throws {
        var filter = RadioDistanceFilter()
        // Walking away from 2m at 1 m/s, clean readings.
        for step in 0..<10 {
            let time = Double(step) * 0.25
            filter.add(2.0 + time * 1.0, at: time)
        }

        let now = 2.25
        let naive = try #require(filter.estimate(at: now, movingAt: 0))
        let projected = try #require(filter.estimate(at: now, movingAt: 1.0))

        #expect(abs(projected - 4.25) < 0.35, "should report roughly where they are now")
        #expect(naive < projected - 0.5, "ignoring their movement reports them closer than they are")
    }

    @Test func silenceBecomesStale() {
        var filter = RadioDistanceFilter()
        filter.add(3.0, at: 0)

        #expect(!filter.isStale(at: 2, after: 5))
        #expect(filter.isStale(at: 9, after: 5),
                "a broadcast that stops — a force-quit, or walking out of range — must expire")
    }

    @Test func nothingHeardMeansNoEstimate() {
        let filter = RadioDistanceFilter()
        #expect(filter.estimate(at: 0) == nil)
        #expect(filter.isStale(at: 0, after: 5))
    }
}
