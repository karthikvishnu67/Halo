//
//  PersonTracker.swift
//  Halo
//
//  Turns per-frame detections into subjects that persist across frames.
//

import CoreGraphics
import Foundation

/// A person the app is following. Unlike `DetectedPerson`, the `id` survives
/// from frame to frame, so a bubble can stay attached to the same subject.
///
/// The id is local and ephemeral: it means "the subject in slot 3 right now",
/// never "this specific human". Walking out of frame and back in produces a
/// new id, by design — the app has no way to recognise anyone.
struct TrackedPerson: Identifiable, Equatable {
    let id: Int
    /// The most recent raw detection — noisy, used for matching.
    var boundingBox: CGRect
    /// The filtered box the UI draws, so a stationary person's bubble
    /// stays put instead of shivering with the detector's noise.
    var smoothedBox: CGRect
    /// Where the halo hangs from, filtered the same way as the box.
    var smoothedHead: CGPoint
    /// How far the head moved per pass, smoothed. Used to project slightly
    /// ahead so filtering doesn't leave the halo trailing a walking person.
    var headVelocity: CGPoint = .zero
    /// Previous raw head position, and a filtered velocity built from it.
    /// The *vector* is filtered rather than the step size, because jitter
    /// alternates direction and therefore cancels itself out, while real
    /// movement accumulates. Filtering step size instead would read a
    /// shivering detection as a sprint.
    var lastMeasuredHead: CGPoint
    var measuredVelocity: CGPoint = .zero
    /// The head position the UI should draw: smoothed, then nudged forward
    /// along the direction of travel to cancel most of the filter's lag.
    var displayHead: CGPoint
    var confidence: Float
    /// When this subject was last actually seen, on a monotonic clock.
    var lastSeenAt: TimeInterval
}

@MainActor
final class PersonTracker {

    /// Below this overlap, two boxes are treated as different people.
    private let matchThreshold: CGFloat = 0.3

    /// How long someone may go unseen before we decide they have left and
    /// forget them. In *time*, because detection runs anywhere between 15 and
    /// 30 passes a second and a count of passes means different things at each
    /// rate.
    ///
    /// Generous on purpose. Losing a track means losing the person's identity,
    /// and they come back as a stranger with somebody else's halo — far worse
    /// than briefly holding on to someone who really did walk away.
    private let retireAfter: TimeInterval = 2.5

    /// A subject keeps their halo drawn for this long after the last sighting.
    /// Long enough to ride out the dropouts that motion blur causes when the
    /// camera is moved, short enough that someone who left doesn't leave a
    /// halo hanging in the air.
    private let drawFor: TimeInterval = 0.5

    /// Smoothing adapts to how fast someone is actually moving, because one
    /// fixed value can't do both jobs: filter hard enough that a still person's
    /// halo doesn't shiver, yet lightly enough that a walking person's doesn't
    /// trail behind. Nearly still uses `slowSmoothing`, moving uses
    /// `fastSmoothing`, and anything between is interpolated.
    private let slowSmoothing: CGFloat = 0.12
    private let fastSmoothing: CGFloat = 0.6

    /// Movement per pass that counts as "properly moving". Roughly a brisk
    /// walk across the frame at the rate detection actually runs.
    private let movingSpeed: CGFloat = 0.02

    /// Velocity is noisier than position, so it is filtered harder.
    private let velocitySmoothing: CGFloat = 0.3

    /// How many passes ahead to project. Exactly cancelling the lag would
    /// overshoot whenever someone changes direction, so this stays under 1.
    private let lead: CGFloat = 0.8

    private var tracks: [TrackedPerson] = []
    private var nextID = 1

    func update(with detections: [DetectedPerson], at now: TimeInterval) -> [TrackedPerson] {
        var unmatchedTracks = Set(tracks.indices)
        var unmatchedDetections = Set(detections.indices)

        // Score every track against every detection, then take the best pairs
        // first. Greedy, but with a handful of people on screen the difference
        // from optimal matching is not worth the complexity.
        var pairs: [(track: Int, detection: Int, score: CGFloat)] = []
        for t in tracks.indices {
            for d in detections.indices {
                if let score = association(of: tracks[t], with: detections[d], at: now) {
                    pairs.append((t, d, score))
                }
            }
        }
        pairs.sort { $0.score > $1.score }

        for pair in pairs {
            guard unmatchedTracks.contains(pair.track),
                  unmatchedDetections.contains(pair.detection) else { continue }

            let measured = detections[pair.detection].boundingBox
            let measuredHead = detections[pair.detection].headPoint

            // How fast they are genuinely travelling decides how much we
            // trust this detection over the filtered history.
            let rawStep = CGPoint(x: measuredHead.x - tracks[pair.track].lastMeasuredHead.x,
                                  y: measuredHead.y - tracks[pair.track].lastMeasuredHead.y)
            let measuredVelocity = blend(tracks[pair.track].measuredVelocity,
                                         towards: rawStep, alpha: velocitySmoothing)
            tracks[pair.track].measuredVelocity = measuredVelocity
            tracks[pair.track].lastMeasuredHead = measuredHead

            let alpha = smoothing(forSpeed: magnitude(measuredVelocity))

            tracks[pair.track].boundingBox = measured
            tracks[pair.track].smoothedBox = blend(tracks[pair.track].smoothedBox,
                                                   towards: measured, alpha: alpha)
            let previousHead = tracks[pair.track].smoothedHead
            let smoothedHead = blend(previousHead,
                                     towards: measuredHead, alpha: alpha)
            let step = CGPoint(x: smoothedHead.x - previousHead.x,
                               y: smoothedHead.y - previousHead.y)
            let velocity = CGPoint(
                x: tracks[pair.track].headVelocity.x + (step.x - tracks[pair.track].headVelocity.x) * velocitySmoothing,
                y: tracks[pair.track].headVelocity.y + (step.y - tracks[pair.track].headVelocity.y) * velocitySmoothing)

            tracks[pair.track].smoothedHead = smoothedHead
            tracks[pair.track].headVelocity = velocity
            tracks[pair.track].displayHead = CGPoint(x: smoothedHead.x + velocity.x * lead,
                                                     y: smoothedHead.y + velocity.y * lead)
            tracks[pair.track].confidence = detections[pair.detection].confidence
            tracks[pair.track].lastSeenAt = now

            unmatchedTracks.remove(pair.track)
            unmatchedDetections.remove(pair.detection)
        }

        // A detection that matched nothing is someone new.
        for d in unmatchedDetections.sorted() {
            // A new subject starts where they were seen, not blended from
            // nowhere, otherwise the first bubble flies in from the corner.
            tracks.append(TrackedPerson(id: nextID,
                                        boundingBox: detections[d].boundingBox,
                                        smoothedBox: detections[d].boundingBox,
                                        smoothedHead: detections[d].headPoint,
                                        lastMeasuredHead: detections[d].headPoint,
                                        displayHead: detections[d].headPoint,
                                        confidence: detections[d].confidence,
                                        lastSeenAt: now))
            nextID += 1
        }

        // Anyone unseen for long enough has left.
        tracks.removeAll { now - $0.lastSeenAt > retireAfter }

        // Everything above stays in `tracks` so it can be re-matched; only
        // recently-seen subjects are handed to the UI.
        return tracks.filter { now - $0.lastSeenAt <= drawFor }
    }

    /// How well a detection explains a track, or nil if it cannot be them.
    ///
    /// Overlap is the good signal, but it fails exactly when the camera moves:
    /// a pan shifts every box at once, and two boxes that are plainly the same
    /// person can end up not overlapping at all. Losing the track then costs
    /// the person their identity. So when overlap fails, a detection of about
    /// the right size, near where this subject was heading, is still taken as
    /// them — ranked below any genuine overlap.
    private func association(of track: TrackedPerson,
                             with detection: DetectedPerson,
                             at now: TimeInterval) -> CGFloat? {
        let elapsed = max(now - track.lastSeenAt, 0)
        let predicted = track.smoothedBox.offsetBy(
            dx: track.measuredVelocity.x * elapsed,
            dy: track.measuredVelocity.y * elapsed)

        let overlap = intersectionOverUnion(predicted, detection.boundingBox)
        if overlap >= matchThreshold {
            return 1 + overlap
        }

        let box = detection.boundingBox
        let larger = max(predicted.width * predicted.height, box.width * box.height)
        let smaller = min(predicted.width * predicted.height, box.width * box.height)
        guard larger > 0, smaller / larger > 0.4 else { return nil }

        let dx = predicted.midX - box.midX
        let dy = predicted.midY - box.midY
        let separation = (dx * dx + dy * dy).squareRoot()
        let reach = max(predicted.width, predicted.height)
        guard separation < reach else { return nil }

        return 1 - separation / reach
    }

    /// Between `slowSmoothing` and `fastSmoothing` depending on speed.
    private func smoothing(forSpeed speed: CGFloat) -> CGFloat {
        let fraction = min(speed / movingSpeed, 1)
        return slowSmoothing + (fastSmoothing - slowSmoothing) * fraction
    }

    private func magnitude(_ point: CGPoint) -> CGFloat {
        (point.x * point.x + point.y * point.y).squareRoot()
    }

    /// Exponential smoothing, applied per edge of the box so position and
    /// size are filtered together.
    private func blend(_ current: CGRect, towards measured: CGRect, alpha: CGFloat) -> CGRect {
        func ease(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
            from + (to - from) * alpha
        }
        return CGRect(x: ease(current.minX, measured.minX),
                      y: ease(current.minY, measured.minY),
                      width: ease(current.width, measured.width),
                      height: ease(current.height, measured.height))
    }

    private func blend(_ current: CGPoint, towards measured: CGPoint, alpha: CGFloat) -> CGPoint {
        CGPoint(x: current.x + (measured.x - current.x) * alpha,
                y: current.y + (measured.y - current.y) * alpha)
    }

    private func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea
        guard unionArea > 0 else { return 0 }

        return intersectionArea / unionArea
    }
}
