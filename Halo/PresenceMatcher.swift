//
//  PresenceMatcher.swift
//  Halo
//
//  Decides which broadcast belongs to which person on screen.
//

import Foundation

/// The join between two senses that never overlap: the camera knows *where*
/// bodies are but not who runs Halo; the radio knows *who* is broadcasting but
/// not where they stand.
///
/// The two failure modes are not equally bad. Failing to place a halo is mild —
/// a balloon appears late. Placing someone's signal above the wrong person's
/// head publishes a message on behalf of somebody who never sent it, which is
/// the one thing the design must never do. Everything below is biased
/// accordingly: when two candidates are equally plausible, the matcher reports
/// nothing rather than guessing.
///
/// It works in real time rather than in update counts, because the two sides
/// arrive at wildly different rates. The camera produces 15-30 passes a second;
/// a phone advertising from someone's pocket may be heard once a second, since
/// iOS slows background advertising down. Treating those as equivalent ticks
/// would make the same movement look ten times faster from one sense than the
/// other.
@MainActor
final class PresenceMatcher {

    /// What the camera contributes: a tracked subject and how far away they
    /// look. Distance is optional because apparent size fails for people who
    /// are seated or half out of frame.
    struct Subject {
        let id: Int
        let distance: Double?
    }

    struct Match {
        let presence: HaloPresence
        let trackID: Int
        let confidence: Double
    }

    struct Outcome {
        /// Broadcasts confidently placed on a tracked person.
        let matched: [Match]
        /// Heard but not placed — behind you, through a wall, or genuinely
        /// ambiguous. Surfaced as an ambient count ("2 nearby"), never guessed
        /// onto somebody.
        let unplaced: [HaloPresence]
    }

    // MARK: tuning

    /// Radio distance is bad enough that a 3-4m disagreement is unremarkable.
    private let levelTolerance = 3.5

    /// Disagreement in *speed*, in metres per second. Loose, because even a
    /// slope fitted across several readings carries real error when each one
    /// is metres out.
    private let trendTolerance = 0.8

    /// How much of the score trend evidence may claim, once there is enough
    /// motion for it to mean anything.
    private let trendShare = 0.6

    /// Speed at which trend evidence becomes fully informative. Set above the
    /// speed that radio noise alone can fake, so that standing still never
    /// looks like walking.
    private let significantMotion = 0.7

    /// Nobody moves faster than this. A reading implying they did is noise —
    /// the commonest radio failure — so it is clamped rather than believed.
    /// Without this, one wild signal reads as a sprint and can shake a halo
    /// off the person it had correctly settled on.
    private let maxPlausibleSpeed = 3.5

    /// Time constants for the two running estimates. Expressed in seconds so
    /// they mean the same thing whether updates arrive slowly or quickly.
    private let confidenceTau: TimeInterval = 0.8
    private let trendTau: TimeInterval = 1.5

    /// Unheard for this long and a broadcast is treated as gone — the person
    /// walked away, went behind a wall, or force-quit the app. iOS gives no
    /// way to keep advertising through a force-quit, so this case is ordinary
    /// rather than exceptional.
    private let staleAfter: TimeInterval = 5

    /// Confidence needed to place a halo on someone for the first time.
    private let bindThreshold = 0.62

    /// How long a broadcast must have been heard before it may be attributed
    /// to anyone at all.
    ///
    /// Without this the matcher commits on its first couple of readings, when
    /// the distance filter has had no chance to reject an obstructed one. In
    /// testing that put a broadcast from someone 2m away onto a bystander at
    /// 6m — a defensible inference from the evidence available, and exactly
    /// the evidence that improves seconds later.
    private let warmUp: TimeInterval = 2.5

    /// A much lower bar to *keep* an existing placement. Safe because a rival
    /// must clear the full bind threshold and margin to take the person, and
    /// because a placement is tied to a tracked body: if they leave, the track
    /// dies and the binding goes with it.
    private let holdThreshold = 0.28

    /// How far ahead of the runner-up the winner must be. This is what makes
    /// the matcher abstain: two equally good candidates produce no margin, and
    /// therefore no halo on either.
    private let requiredMargin = 0.12

    /// Taking a placement away from an established one demands far more. When
    /// two people cross paths at the same distance the radio genuinely reports
    /// them in the wrong order for seconds at a time, so the matcher holds what
    /// it decided when the evidence was clear.
    ///
    /// Scaled by how well-established the incumbent actually is, though. A
    /// placement whose own confidence has fallen well below the bar it was
    /// created with has no claim to that protection — otherwise an early
    /// mistake, made before the evidence matured, is defended forever.
    private let stealMargin = 0.3

    // MARK: state

    private struct PairKey: Hashable {
        let presenceID: String
        let trackID: Int
    }

    private var confidence: [PairKey: Double] = [:]
    private var bindings: [String: Int] = [:]

    private var filters: [String: RadioDistanceFilter] = [:]
    private var lastReadingAt: [String: TimeInterval] = [:]
    private var lastPresenceDistance: [String: Double] = [:]
    private var presenceSpeed: [String: Double] = [:]

    private var lastSubjectDistance: [Int: Double] = [:]
    private var lastSubjectAt: [Int: TimeInterval] = [:]
    private var subjectSpeed: [Int: Double] = [:]

    private var lastUpdateAt: TimeInterval?

    // MARK: matching

    /// - Parameter now: a monotonic clock in seconds (`ProcessInfo.systemUptime`
    ///   in the app; a simulated counter in tests).
    func update(subjects: [Subject],
                presences: [HaloPresence],
                now: TimeInterval) -> Outcome {

        let elapsed = lastUpdateAt.map { max(now - $0, 0) } ?? 0
        lastUpdateAt = now

        ingest(presences, at: now)

        // A broadcast nobody has heard lately is gone, not merely unplaced.
        let live = presences.filter { presence in
            !(filters[presence.id]?.isStale(at: now, after: staleAfter) ?? true)
        }

        forgetDeparted(subjects: subjects, presences: live)
        updateSubjectSpeeds(subjects, at: now)
        scorePairs(subjects: subjects, presences: live, elapsed: elapsed, now: now)

        bindings = commitBindings(subjects: subjects, presences: live)

        let byID = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
        let matched = bindings.compactMap { presenceID, trackID -> Match? in
            guard let presence = byID[presenceID] else { return nil }
            return Match(presence: presence,
                         trackID: trackID,
                         confidence: confidence[PairKey(presenceID: presenceID,
                                                        trackID: trackID)] ?? 0)
        }
        let placed = Set(bindings.keys)

        return Outcome(matched: matched.sorted { $0.trackID < $1.trackID },
                       unplaced: live.filter { !placed.contains($0.id) })
    }

    /// Feeds new radio readings into their filters. A presence may be reported
    /// on every call while only being *heard* occasionally, so readings are
    /// taken once, when they are actually new.
    private func ingest(_ presences: [HaloPresence], at now: TimeInterval) {
        for presence in presences {
            guard lastReadingAt[presence.id] != presence.heardAt else { continue }

            var filter = filters[presence.id] ?? RadioDistanceFilter()
            filter.add(presence.rawDistance, at: presence.heardAt)
            filters[presence.id] = filter
            presenceSpeed[presence.id] = filter.speed(at: now)
            lastReadingAt[presence.id] = presence.heardAt
        }
    }

    private func updateSubjectSpeeds(_ subjects: [Subject], at now: TimeInterval) {
        for subject in subjects {
            guard let distance = subject.distance else { continue }

            if let previous = lastSubjectDistance[subject.id],
               let previousAt = lastSubjectAt[subject.id],
               now > previousAt {
                let gap = now - previousAt
                let speed = clampedSpeed((distance - previous) / gap)
                subjectSpeed[subject.id] = smooth(subjectSpeed[subject.id] ?? 0,
                                                  towards: speed,
                                                  over: gap,
                                                  tau: trendTau)
            }
            lastSubjectDistance[subject.id] = distance
            lastSubjectAt[subject.id] = now
        }
    }

    private func scorePairs(subjects: [Subject],
                            presences: [HaloPresence],
                            elapsed: TimeInterval,
                            now: TimeInterval) {
        var seen: Set<PairKey> = []

        for subject in subjects {
            guard let cameraDistance = subject.distance else { continue }

            for presence in presences {
                guard let radioDistance = filters[presence.id]?.estimate(at: now) else { continue }

                let key = PairKey(presenceID: presence.id, trackID: subject.id)
                seen.insert(key)

                let level = agreement(abs(cameraDistance - radioDistance),
                                      tolerance: levelTolerance)

                let ourSpeed = subjectSpeed[subject.id] ?? 0
                let theirSpeed = presenceSpeed[presence.id] ?? 0
                let trend = agreement(abs(ourSpeed - theirSpeed), tolerance: trendTolerance)

                // Trend evidence only counts to the extent that something is
                // actually moving. Two stationary candidates "agree" perfectly
                // on trend while telling us nothing, and treating that as
                // evidence would manufacture confidence out of stillness.
                let motion = max(abs(ourSpeed), abs(theirSpeed))
                let informative = min(motion / significantMotion, 1)
                let share = trendShare * informative
                let instant = level * (1 - share) + trend * share

                confidence[key] = smooth(confidence[key] ?? 0,
                                         towards: instant,
                                         over: elapsed,
                                         tau: confidenceTau)
            }
        }

        // Pairs with no evidence this pass fade rather than holding their old
        // score — a subject whose distance became unknowable shouldn't keep a
        // halo on the strength of stale agreement.
        for key in confidence.keys where !seen.contains(key) {
            confidence[key] = smooth(confidence[key] ?? 0,
                                     towards: 0,
                                     over: elapsed,
                                     tau: confidenceTau)
        }
    }

    /// Claims the best pairs first, and only where the winner is clearly ahead
    /// of the alternatives. One presence per person, one person per presence.
    private func commitBindings(subjects: [Subject], presences: [HaloPresence]) -> [String: Int] {
        let liveSubjects = Set(subjects.map(\.id))
        let livePresences = Set(presences.map(\.id))

        let candidates = confidence
            .filter { livePresences.contains($0.key.presenceID) && liveSubjects.contains($0.key.trackID) }
            .sorted { $0.value > $1.value }

        var committed: [String: Int] = [:]
        var claimedTracks: Set<Int> = []

        for (key, score) in candidates {
            guard committed[key.presenceID] == nil,
                  !claimedTracks.contains(key.trackID) else { continue }

            let alreadyBound = bindings[key.presenceID] == key.trackID
            guard score >= (alreadyBound ? holdThreshold : bindThreshold) else { continue }

            // A broadcast heard only moments ago cannot yet be attributed to
            // anyone: its distance has not been filtered enough to trust.
            if !alreadyBound {
                let observed = filters[key.presenceID]?.observedSpan(at: lastUpdateAt ?? 0) ?? 0
                guard observed >= warmUp else { continue }
            }

            if !alreadyBound {
                // Is this pair trying to displace an existing placement —
                // either taking this broadcast off someone, or taking this
                // person off another broadcast?
                var incumbent = 0.0
                if let heldTrack = bindings[key.presenceID] {
                    incumbent = max(incumbent, confidence[PairKey(presenceID: key.presenceID,
                                                                 trackID: heldTrack)] ?? 0)
                }
                if let heldPresence = bindings.first(where: { $0.value == key.trackID })?.key {
                    incumbent = max(incumbent, confidence[PairKey(presenceID: heldPresence,
                                                                 trackID: key.trackID)] ?? 0)
                }
                if incumbent > 0 {
                    let established = min(incumbent / bindThreshold, 1)
                    guard score - incumbent >= stealMargin * established else { continue }
                }

                // The runner-up on *either* axis: another person this broadcast
                // might belong to, or another broadcast this person might own.
                let rival = candidates
                    .filter { other in
                        other.key != key
                            && (other.key.presenceID == key.presenceID || other.key.trackID == key.trackID)
                    }
                    .map(\.value)
                    .max() ?? 0

                guard score - rival >= requiredMargin else { continue }
            }

            committed[key.presenceID] = key.trackID
            claimedTracks.insert(key.trackID)
        }

        return committed
    }

    private func forgetDeparted(subjects: [Subject], presences: [HaloPresence]) {
        let liveSubjects = Set(subjects.map(\.id))
        let livePresences = Set(presences.map(\.id))

        confidence = confidence.filter {
            liveSubjects.contains($0.key.trackID) && livePresences.contains($0.key.presenceID)
        }
        bindings = bindings.filter {
            livePresences.contains($0.key) && liveSubjects.contains($0.value)
        }
        lastSubjectDistance = lastSubjectDistance.filter { liveSubjects.contains($0.key) }
        lastSubjectAt = lastSubjectAt.filter { liveSubjects.contains($0.key) }
        subjectSpeed = subjectSpeed.filter { liveSubjects.contains($0.key) }

        filters = filters.filter { livePresences.contains($0.key) }
        lastReadingAt = lastReadingAt.filter { livePresences.contains($0.key) }
        lastPresenceDistance = lastPresenceDistance.filter { livePresences.contains($0.key) }
        presenceSpeed = presenceSpeed.filter { livePresences.contains($0.key) }
    }

    #if DEBUG
    /// What the matcher currently believes, for diagnosing why a halo did or
    /// didn't appear. Worth keeping: guessing at this cost more than one
    /// wrong fix.
    struct Snapshot {
        let filtered: [String: Double]
        let speeds: [String: Double]
        let confidence: [String: Double]
    }

    func snapshot(at now: TimeInterval) -> Snapshot {
        var filtered: [String: Double] = [:]
        for (id, filter) in filters {
            filtered[id] = filter.estimate(at: now)
        }
        let scores = Dictionary(uniqueKeysWithValues:
            confidence.map { ("\($0.key.presenceID)->\($0.key.trackID)", $0.value) })
        return Snapshot(filtered: filtered, speeds: presenceSpeed, confidence: scores)
    }
    #endif

    /// Exponential smoothing where the weight depends on *time* passed, so the
    /// same estimate behaves identically whether it is fed 30 times a second or
    /// once a second.
    private func smooth(_ current: Double,
                        towards measured: Double,
                        over elapsed: TimeInterval,
                        tau: TimeInterval) -> Double {
        guard elapsed > 0 else { return current }
        let alpha = 1 - exp(-elapsed / tau)
        return current + (measured - current) * alpha
    }

    private func clampedSpeed(_ speed: Double) -> Double {
        min(max(speed, -maxPlausibleSpeed), maxPlausibleSpeed)
    }

    /// 1 when two readings agree exactly, falling off smoothly with disagreement.
    private func agreement(_ error: Double, tolerance: Double) -> Double {
        exp(-error / tolerance)
    }
}
