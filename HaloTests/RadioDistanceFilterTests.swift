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

        // Not exact, and shouldn't claim to be: the sample happens to trend
        // slightly upward, so the filter reasonably reads a little movement
        // into it and projects accordingly. What matters is that it lands near
        // the readings that got through rather than near the average of all of
        // them, which the blocked ones drag out past 5m.
        #expect(abs(estimate - 3.0) < 1.0, "should land near the unobstructed truth of 3m")
        #expect(estimate < mean - 1.5, "and well below the average")
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
        let speed = filter.speed(at: now)
        let estimate = try #require(filter.estimate(at: now))

        #expect(abs(speed - 1.0) < 0.15, "should work out they are walking away at about 1 m/s")
        #expect(abs(estimate - 4.25) < 0.5, "and report roughly where they are now, not where they were")
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

    /// The failure this whole approach exists to avoid: a stationary person,
    /// heard once a second with metres of noise, must not appear to be walking.
    /// Believing that made the matcher reject the correct pairing, because the
    /// camera could plainly see the person standing still.
    @Test func noiseOnAStationaryPersonIsNotMistakenForWalking() {
        var filter = RadioDistanceFilter()
        // True distance 2m throughout; readings scattered the way a body in
        // the way scatters them.
        let readings = [5.3, 4.1, 1.4, 2.0, 5.6, 2.7, 2.5, 2.3]
        for (index, reading) in readings.enumerated() {
            filter.add(reading, at: Double(index))
        }

        #expect(abs(filter.speed(at: 7)) < 0.7,
                "a slope fitted across the window should stay near zero")
    }
}
