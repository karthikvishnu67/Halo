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

    /// Movement per pass, where disagreement is far more meaningful.
    private let trendTolerance = 0.35

    /// How much of the score trend evidence may claim, once there is enough
    /// motion for it to mean anything.
    private let trendShare = 0.6

    /// Movement per pass at which trend evidence is fully informative.
    private let significantMotion = 0.25

    private let confidenceSmoothing = 0.25
    private let trendSmoothing = 0.3

    /// Nobody moves this far between passes. A reading that implies they did
    /// is noise — the commonest radio failure — so it is clamped rather than
    /// believed. Without this, one wild signal reads as a sprint and can shake
    /// a halo off the person it had correctly settled on.
    private let maxPlausibleStep = 0.8

    /// Confidence needed to place a halo on someone for the first time.
    private let bindThreshold = 0.62

    /// A much lower bar to *keep* an existing placement. This is safe because
    /// a rival can only take the person by clearing the full bind threshold
    /// and margin, and because the placement is tied to a tracked body: if
    /// that person leaves, the track dies and the binding goes with it. So the
    /// only thing a low bar risks is holding a placement that was originally
    /// established on strong evidence — which is the safer default than
    /// dropping and re-guessing.
    private let holdThreshold = 0.28

    /// How far ahead of the runner-up the winner must be. This is what makes
    /// the matcher abstain: two equally good candidates produce no margin, and
    /// therefore no halo on either.
    private let requiredMargin = 0.12

    /// Taking a placement away from an established one demands far more than
    /// making a fresh one. When two people cross paths at the same distance,
    /// the radio genuinely reports the wrong order for seconds at a time — the
    /// evidence itself is ambiguous, and no scoring rule can recover truth
    /// that isn't in the data. So the matcher holds what it decided when the
    /// evidence *was* clear, and only revises on evidence far stronger than
    /// the noise.
    private let stealMargin = 0.3

    // MARK: state

    private struct PairKey: Hashable {
        let presenceID: String
        let trackID: Int
    }

    private var confidence: [PairKey: Double] = [:]
    private var lastSubjectDistance: [Int: Double] = [:]
    private var lastPresenceDistance: [String: Double] = [:]
    private var subjectTrend: [Int: Double] = [:]
    private var presenceTrend: [String: Double] = [:]
    private var bindings: [String: Int] = [:]

    // MARK: matching

    func update(subjects: [Subject], presences: [HaloPresence]) -> Outcome {
        forgetDeparted(subjects: subjects, presences: presences)
        updateTrends(subjects: subjects, presences: presences)
        scorePairs(subjects: subjects, presences: presences)

        bindings = commitBindings(subjects: subjects, presences: presences)

        let byID = Dictionary(uniqueKeysWithValues: presences.map { ($0.id, $0) })
        let matched = bindings.compactMap { presenceID, trackID -> Match? in
            guard let presence = byID[presenceID] else { return nil }
            return Match(presence: presence,
                         trackID: trackID,
                         confidence: confidence[PairKey(presenceID: presenceID,
                                                        trackID: trackID)] ?? 0)
        }
        let placed = Set(bindings.keys)

        return Outcome(matched: matched.sorted { $0.trackID < $1.trackID },
                       unplaced: presences.filter { !placed.contains($0.id) })
    }

    /// How far each side has moved since the last pass, smoothed — a single
    /// noisy step means little, a consistent drift means a lot.
    private func updateTrends(subjects: [Subject], presences: [HaloPresence]) {
        for subject in subjects {
            guard let distance = subject.distance else { continue }
            if let last = lastSubjectDistance[subject.id] {
                let previous = subjectTrend[subject.id] ?? 0
                let step = clampedStep(distance - last)
                subjectTrend[subject.id] = previous + (step - previous) * trendSmoothing
            }
            lastSubjectDistance[subject.id] = distance
        }

        for presence in presences {
            if let last = lastPresenceDistance[presence.id] {
                let previous = presenceTrend[presence.id] ?? 0
                let step = clampedStep(presence.estimatedDistance - last)
                presenceTrend[presence.id] = previous + (step - previous) * trendSmoothing
            }
            lastPresenceDistance[presence.id] = presence.estimatedDistance
        }
    }

    private func scorePairs(subjects: [Subject], presences: [HaloPresence]) {
        var seen: Set<PairKey> = []

        for subject in subjects {
            guard let cameraDistance = subject.distance else { continue }

            for presence in presences {
                let key = PairKey(presenceID: presence.id, trackID: subject.id)
                seen.insert(key)

                let level = agreement(abs(cameraDistance - presence.estimatedDistance),
                                      tolerance: levelTolerance)

                let ourTrend = subjectTrend[subject.id] ?? 0
                let theirTrend = presenceTrend[presence.id] ?? 0
                let trend = agreement(abs(ourTrend - theirTrend), tolerance: trendTolerance)

                // Trend evidence only counts to the extent that something is
                // actually moving. Two stationary candidates "agree" perfectly
                // on trend while telling us nothing, and treating that as
                // evidence would manufacture confidence out of stillness.
                let motion = max(abs(ourTrend), abs(theirTrend))
                let informative = min(motion / significantMotion, 1)
                let share = trendShare * informative
                let instant = level * (1 - share) + trend * share

                let previous = confidence[key] ?? 0
                confidence[key] = previous + (instant - previous) * confidenceSmoothing
            }
        }

        // Pairs with no evidence this pass fade rather than holding their old
        // score — a subject whose distance became unknowable shouldn't keep a
        // halo on the strength of stale agreement.
        for key in confidence.keys where !seen.contains(key) {
            confidence[key] = (confidence[key] ?? 0) * (1 - confidenceSmoothing)
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
                    guard score - incumbent >= stealMargin else { continue }
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
        subjectTrend = subjectTrend.filter { liveSubjects.contains($0.key) }
        lastPresenceDistance = lastPresenceDistance.filter { livePresences.contains($0.key) }
        presenceTrend = presenceTrend.filter { livePresences.contains($0.key) }
    }

    private func clampedStep(_ step: Double) -> Double {
        min(max(step, -maxPlausibleStep), maxPlausibleStep)
    }

    /// 1 when two readings agree exactly, falling off smoothly with disagreement.
    private func agreement(_ error: Double, tolerance: Double) -> Double {
        exp(-error / tolerance)
    }
}
