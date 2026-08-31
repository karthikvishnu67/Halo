//
//  SimulatedRadio.swift
//  Halo
//
//  A stand-in for Bluetooth, so the matcher can be watched working.
//

import Foundation

/// Small deterministic generator, so a simulated run can be repeated exactly.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Pretends some of the people on screen are carrying phones that broadcast.
///
/// This exists so the whole V2 chain — broadcast heard, distance estimated,
/// matched to a body, halo placed — can be exercised on a real phone before any
/// Bluetooth code exists. Crucially it simulates the *bad* parts too: readings
/// biased long by obstruction, and adverts arriving about once a second, which
/// is what iOS allows an app advertising from someone's pocket.
@MainActor
@Observable
final class SimulatedRadio {

    /// Someone whose phone we pretend is broadcasting.
    ///
    /// Their identity is fixed for the life of the app, and deliberately owes
    /// nothing to the camera. A broadcast comes from a radio: it does not stop
    /// existing, or turn into somebody else, because the camera briefly lost
    /// sight of its owner. Tying these to track ids meant a shaken camera
    /// produced a *different person's* halo, which is exactly backwards.
    private struct Broadcaster {
        let presenceID: String
        let profile: HaloProfile
        /// Which visible person they are, counting from the nearest.
        let followsRank: Int
        var lastAdvertAt: TimeInterval
        var lastReading: Double
    }

    /// How often a simulated phone is heard. Roughly what iOS allows for an
    /// app advertising in the background.
    var advertInterval: TimeInterval = 1.0

    /// Whether to include a broadcast from someone who isn't in view — behind
    /// you, or through a wall. It should never be placed on anyone.
    var includeUnseenBroadcaster = true

    private var roster: [Broadcaster]
    private var rng: SplitMix64

    /// - Parameter seed: fix it to replay exactly the same noise, which is what
    ///   the tests do. Left out, every run differs.
    init(seed: UInt64? = nil) {
        rng = SplitMix64(seed: seed ?? UInt64.random(in: 0..<UInt64.max))
        // Ranks chosen so somebody visible is always *not* broadcasting: the
        // people with no halo are as much the point as the people with one.
        roster = [
            Broadcaster(presenceID: "sim-a", profile: HaloProfile.cast[0],
                        followsRank: 0, lastAdvertAt: -.greatestFiniteMagnitude, lastReading: 0),
            Broadcaster(presenceID: "sim-b", profile: HaloProfile.cast[2],
                        followsRank: 2, lastAdvertAt: -.greatestFiniteMagnitude, lastReading: 0),
            Broadcaster(presenceID: "sim-c", profile: HaloProfile.cast[4],
                        followsRank: 3, lastAdvertAt: -.greatestFiniteMagnitude, lastReading: 0),
        ]
    }

    func presences(for subjects: [PresenceMatcher.Subject],
                   at now: TimeInterval) -> [HaloPresence] {
        // Ranked by distance rather than by track id, so a broadcaster keeps
        // following the same human even when the camera loses them for a
        // moment and gives them a new id.
        let ranked = subjects
            .compactMap { subject in subject.distance.map { (subject: subject, distance: $0) } }
            .sorted { $0.distance < $1.distance }

        var heard: [HaloPresence] = []

        for index in roster.indices {
            let rank = roster[index].followsRank
            guard rank < ranked.count else { continue }

            // A new advert only occasionally, exactly as a backgrounded phone
            // would manage.
            if now - roster[index].lastAdvertAt >= advertInterval {
                roster[index].lastAdvertAt = now
                roster[index].lastReading = reading(for: ranked[rank].distance)
            }

            heard.append(HaloPresence(id: roster[index].presenceID,
                                      profile: roster[index].profile,
                                      rawDistance: roster[index].lastReading,
                                      heardAt: roster[index].lastAdvertAt))
        }

        if includeUnseenBroadcaster {
            heard.append(unseenBroadcaster(at: now))
        }

        return heard
    }

    /// Radio distance, with the error shaped the way the real thing is: mostly
    /// too long, because bodies and pockets absorb the signal, and only rarely
    /// short. `RadioDistanceFilter` is built to see through exactly this.
    private func reading(for trueDistance: Double) -> Double {
        let obstructed = Double.random(in: 0...1, using: &rng) < 0.45
        let error = obstructed ? Double.random(in: 1.0...4.0, using: &rng)
                               : Double.random(in: -0.8...1.0, using: &rng)
        return max(0.3, trueDistance + error)
    }

    /// A broadcast from somebody the camera cannot see. The matcher should
    /// report it as heard-but-unplaced rather than hanging it on a stranger.
    ///
    /// Deliberately far off. Placed nearer, it competes with whoever is at a
    /// similar distance, and the matcher then correctly refuses to place either
    /// — right behaviour, but it makes the simulator look broken rather than
    /// careful. Ambiguity between two *visible* people is the interesting case
    /// and the matcher's own tests cover it.
    private let unseenDistance: Double = 22
    private var unseenAdvertAt: TimeInterval = 0
    private var unseenReading: Double = 22

    private func unseenBroadcaster(at now: TimeInterval) -> HaloPresence {
        if now - unseenAdvertAt >= advertInterval {
            unseenAdvertAt = now
            unseenReading = reading(for: unseenDistance)
        }
        return HaloPresence(id: "sim-unseen",
                            profile: HaloProfile.cast[HaloProfile.cast.count - 1],
                            rawDistance: unseenReading,
                            heardAt: unseenAdvertAt)
    }

}
