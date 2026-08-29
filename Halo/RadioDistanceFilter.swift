//
//  RadioDistanceFilter.swift
//  Halo
//
//  Turns a stream of noisy radio distances into something worth believing.
//

import Foundation

/// Radio distance error is *asymmetric*, and that is the whole idea here.
///
/// A signal is weakened by anything in the way — a body, a bag, a coat pocket —
/// and a weaker signal reads as further away. Almost nothing makes a phone read
/// *closer* than it really is. So a window of recent readings is a set of
/// samples that are each either about right or too long, and the smallest of
/// them is the closest to the truth.
///
/// Averaging would bake the obstruction bias in. Taking a low quantile instead
/// discards the blocked readings and keeps the ones that got through, which is
/// exactly what happens when someone has their phone in a front pocket and
/// turns around.
///
/// That argument only holds for readings *of the same true distance*, though.
/// Over a window in which someone is walking, their distance genuinely changes,
/// and a naive low quantile stops meaning "least obstructed" and starts meaning
/// "wherever they were earliest" — which made the matcher badly under-confident
/// about moving people when this was first written. So each reading is first
/// projected forward to now along their estimated speed. What is left is
/// obstruction noise, which is what the quantile is for.
struct RadioDistanceFilter {

    /// How much history to consider.
    ///
    /// This has to be long enough to *contain* an unobstructed reading. A
    /// backgrounded phone is heard about once a second, so a three-second
    /// window holds barely three samples — too few for a quantile to reject
    /// anything, and the estimate drifts far enough that a broadcast can be
    /// attributed to a bystander standing at the wrong distance. Six seconds
    /// is affordable because movement is now removed by a fitted slope rather
    /// than assumed away.
    private let window: TimeInterval = 6

    /// Which quantile to take. Not the minimum: a single wild reflection can
    /// read absurdly close, and picking the outright lowest would chase it.
    private let quantile = 0.2

    /// The furthest a reading may be carried forward. The speed used to project
    /// is itself estimated from these same noisy readings, so over a long
    /// enough reach a wrong speed does more damage than the movement it was
    /// meant to correct.
    private let maxProjection: Double = 4.0

    /// Nobody walks faster than this in the situations Halo cares about.
    private let maxSpeed: Double = 2.5

    /// Fewer readings than this and any slope is noise.
    private let minimumSamplesForSpeed = 3

    private var readings: [(distance: Double, at: TimeInterval)] = []

    mutating func add(_ distance: Double, at time: TimeInterval) {
        readings.append((distance, time))
        readings.removeAll { time - $0.at > window }
    }

    /// The de-biased distance, or nil if nothing recent enough to judge.
    ///
    func estimate(at now: TimeInterval) -> Double? {
        let speed = self.speed(at: now)
        let projected = readings
            .filter { now - $0.at <= window }
            .map { reading in
                let shift = speed * (now - reading.at)
                return reading.distance + min(max(shift, -maxProjection), maxProjection)
            }
            .sorted()
        guard !projected.isEmpty else { return nil }

        let index = Int((Double(projected.count - 1) * quantile).rounded())
        return max(projected[index], 0.1)
    }

    /// How fast they are moving away, in metres per second, negative when
    /// approaching.
    ///
    /// Fitted across the whole window rather than taken from the difference
    /// between consecutive readings. With adverts arriving perhaps once a
    /// second and metres of noise on each, consecutive differences imply a
    /// stationary person is sprinting — and a matcher that believes that will
    /// reject the very pairing that is correct, because the camera can plainly
    /// see they are standing still. A slope across several readings averages
    /// most of that away.
    func speed(at now: TimeInterval) -> Double {
        let recent = readings.filter { now - $0.at <= window }
        guard recent.count >= minimumSamplesForSpeed else { return 0 }

        let meanTime = recent.map(\.at).reduce(0, +) / Double(recent.count)
        let meanDistance = recent.map(\.distance).reduce(0, +) / Double(recent.count)

        var covariance = 0.0
        var variance = 0.0
        for reading in recent {
            let dt = reading.at - meanTime
            covariance += dt * (reading.distance - meanDistance)
            variance += dt * dt
        }
        guard variance > 0 else { return 0 }

        return min(max(covariance / variance, -maxSpeed), maxSpeed)
    }

    /// How long this broadcast has been under observation, within the window.
    /// A filter that has only just started cannot have rejected anything.
    func observedSpan(at now: TimeInterval) -> TimeInterval {
        let recent = readings.filter { now - $0.at <= window }
        guard let first = recent.first, let last = recent.last else { return 0 }
        return last.at - first.at
    }

    /// True when nothing has been heard for a while — the broadcaster walked
    /// off, went behind a wall, or force-quit the app.
    func isStale(at now: TimeInterval, after timeout: TimeInterval) -> Bool {
        guard let last = readings.last else { return true }
        return now - last.at > timeout
    }
}
