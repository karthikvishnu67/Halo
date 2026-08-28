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

    /// How much history to consider. Long enough to catch a clear reading
    /// between obstructed ones, short enough that projecting across it stays
    /// trustworthy.
    private let window: TimeInterval = 3

    /// Which quantile to take. Not the minimum: a single wild reflection can
    /// read absurdly close, and picking the outright lowest would chase it.
    private let quantile = 0.25

    private var readings: [(distance: Double, at: TimeInterval)] = []

    mutating func add(_ distance: Double, at time: TimeInterval) {
        readings.append((distance, time))
        readings.removeAll { time - $0.at > window }
    }

    /// The de-biased distance, or nil if nothing recent enough to judge.
    ///
    /// - Parameter speed: how fast they are moving away in metres per second
    ///   (negative when approaching). Used to carry older readings forward to
    ///   now, so that movement is not mistaken for interference.
    func estimate(at now: TimeInterval, movingAt speed: Double = 0) -> Double? {
        let projected = readings
            .filter { now - $0.at <= window }
            .map { $0.distance + speed * (now - $0.at) }
            .sorted()
        guard !projected.isEmpty else { return nil }

        let index = Int((Double(projected.count - 1) * quantile).rounded())
        return max(projected[index], 0.1)
    }

    /// True when nothing has been heard for a while — the broadcaster walked
    /// off, went behind a wall, or force-quit the app.
    func isStale(at now: TimeInterval, after timeout: TimeInterval) -> Bool {
        guard let last = readings.last else { return true }
        return now - last.at > timeout
    }
}
