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
    private struct Broadcaster {
        let presenceID: String
        let profile: HaloProfile
        var lastAdvertAt: TimeInterval
        var lastReading: Double
    }

    /// How often a simulated phone is heard. Roughly what iOS allows for an
    /// app advertising in the background.
    var advertInterval: TimeInterval = 1.0

    /// Whether to include a broadcast from someone who isn't in view — behind
    /// you, or through a wall. It should never be placed on anyone.
    var includeUnseenBroadcaster = true

    private var broadcasters: [Int: Broadcaster] = [:]
    private var nextProfile = 0
    private var rng: SplitMix64

    /// - Parameter seed: fix it to replay exactly the same noise, which is what
    ///   the tests do. Left out, every run differs.
    init(seed: UInt64? = nil) {
        rng = SplitMix64(seed: seed ?? UInt64.random(in: 0..<UInt64.max))
    }

    /// Which tracked people are pretending to run Halo. Odd track ids do, even
    /// ones don't — deliberately visible in the demo, because the people with
    /// no halo are the point: someone who hasn't opted in is absent from the
    /// system rather than marked as a non-user.
    private func isHaloUser(_ trackID: Int) -> Bool {
        trackID % 2 == 1
    }

    func presences(for subjects: [PresenceMatcher.Subject],
                   at now: TimeInterval) -> [HaloPresence] {
        forgetDeparted(subjects)

        var heard: [HaloPresence] = []

        for subject in subjects where isHaloUser(subject.id) {
            guard let trueDistance = subject.distance else { continue }

            var broadcaster = broadcasters[subject.id] ?? adopt(subject.id, at: now, distance: trueDistance)

            // A new advert only occasionally, exactly as a backgrounded phone
            // would manage.
            if now - broadcaster.lastAdvertAt >= advertInterval {
                broadcaster.lastAdvertAt = now
                broadcaster.lastReading = reading(for: trueDistance)
            }
            broadcasters[subject.id] = broadcaster

            heard.append(HaloPresence(id: broadcaster.presenceID,
                                      profile: broadcaster.profile,
                                      rawDistance: broadcaster.lastReading,
                                      heardAt: broadcaster.lastAdvertAt))
        }

        if includeUnseenBroadcaster {
            heard.append(unseenBroadcaster(at: now))
        }

        return heard
    }

    private func adopt(_ trackID: Int, at now: TimeInterval, distance: Double) -> Broadcaster {
        let profile = HaloProfile.cast[nextProfile % HaloProfile.cast.count]
        nextProfile += 1
        return Broadcaster(presenceID: "sim-\(trackID)",
                           profile: profile,
                           lastAdvertAt: now,
                           lastReading: reading(for: distance))
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

    private func forgetDeparted(_ subjects: [PresenceMatcher.Subject]) {
        let live = Set(subjects.map(\.id))
        broadcasters = broadcasters.filter { live.contains($0.key) }
    }
}
