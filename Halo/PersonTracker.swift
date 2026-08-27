//
//  PersonTracker.swift
//  Halo
//
//  Turns per-frame detections into subjects that persist across frames.
//

import CoreGraphics

/// A person the app is following. Unlike `DetectedPerson`, the `id` survives
/// from frame to frame, so a bubble can stay attached to the same subject.
///
/// The id is local and ephemeral: it means "the subject in slot 3 right now",
/// never "this specific human". Walking out of frame and back in produces a
/// new id, by design — the app has no way to recognise anyone.
struct TrackedPerson: Identifiable {
    let id: Int
    var boundingBox: CGRect
    var confidence: Float
    /// Consecutive detection passes in which this subject wasn't matched.
    var missedFrames: Int = 0
}

@MainActor
final class PersonTracker {

    /// Below this overlap, two boxes are treated as different people.
    private let matchThreshold: CGFloat = 0.3

    /// How many detection passes a subject may go unmatched before we drop it.
    /// This is what stops the flicker: a person who vanishes for two frames
    /// keeps their track instead of being reborn as a new subject.
    private let missTolerance = 8

    /// A track is still drawn for this many missed passes. Kept much shorter
    /// than `missTolerance` so a brief dropout doesn't blink, while someone who
    /// actually left doesn't leave a box hanging in empty space.
    private let visibleAfterMisses = 2

    private var tracks: [TrackedPerson] = []
    private var nextID = 1

    func update(with detections: [DetectedPerson]) -> [TrackedPerson] {
        var unmatchedTracks = Set(tracks.indices)
        var unmatchedDetections = Set(detections.indices)

        // Score every track against every detection, then take the best pairs
        // first. Greedy, but with a handful of people on screen the difference
        // from optimal matching is not worth the complexity.
        var pairs: [(track: Int, detection: Int, overlap: CGFloat)] = []
        for t in tracks.indices {
            for d in detections.indices {
                let overlap = intersectionOverUnion(tracks[t].boundingBox,
                                                    detections[d].boundingBox)
                if overlap >= matchThreshold {
                    pairs.append((t, d, overlap))
                }
            }
        }
        pairs.sort { $0.overlap > $1.overlap }

        for pair in pairs {
            guard unmatchedTracks.contains(pair.track),
                  unmatchedDetections.contains(pair.detection) else { continue }

            tracks[pair.track].boundingBox = detections[pair.detection].boundingBox
            tracks[pair.track].confidence = detections[pair.detection].confidence
            tracks[pair.track].missedFrames = 0

            unmatchedTracks.remove(pair.track)
            unmatchedDetections.remove(pair.detection)
        }

        // A detection that matched nothing is someone new.
        for d in unmatchedDetections.sorted() {
            tracks.append(TrackedPerson(id: nextID,
                                        boundingBox: detections[d].boundingBox,
                                        confidence: detections[d].confidence))
            nextID += 1
        }

        // A track that matched nothing is either briefly lost or gone.
        for t in unmatchedTracks {
            tracks[t].missedFrames += 1
        }
        tracks.removeAll { $0.missedFrames > missTolerance }

        // Everything above stays in `tracks` so it can be re-matched; only
        // recently-seen subjects are handed to the UI.
        return tracks.filter { $0.missedFrames <= visibleAfterMisses }
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
