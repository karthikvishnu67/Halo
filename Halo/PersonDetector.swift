//
//  PersonDetector.swift
//  Halo
//
//  Runs Vision's human-rectangle detector over camera frames.
//

import CoreVideo
import Observation
import os
import Vision

/// One person Vision found in a single frame.
///
/// The `id` is Vision's per-observation UUID: it is *not* stable across frames,
/// so it must not be treated as a lasting identity. Frame-to-frame identity
/// arrives with tracking in V1.3.
struct DetectedPerson: Identifiable {
    let id: UUID
    /// Normalized 0-1, top-left origin — i.e. AVFoundation's "metadata output"
    /// space, which the preview layer can convert into view coordinates.
    let boundingBox: CGRect
    let confidence: Float
}

@MainActor
@Observable
final class PersonDetector {

    /// Subjects with identity that persists across frames.
    private(set) var people: [TrackedPerson] = []

    @ObservationIgnored private let tracker = PersonTracker()
    @ObservationIgnored private let profiles = ProfileDirectory()

    func profile(for id: Int) -> HaloProfile {
        profiles.profile(for: id)
    }

    /// Detection is slower than the camera's frame rate. Rather than letting
    /// frames queue up (which shows as lag), we keep exactly one request in
    /// flight and drop every frame that arrives while it is running.
    @ObservationIgnored private let isDetecting = OSAllocatedUnfairLock(initialState: false)

    /// Called on the video queue for (nearly) every camera frame.
    nonisolated func detect(in pixelBuffer: CVPixelBuffer) {
        let shouldStart = isDetecting.withLock { running in
            if running { return false }
            running = true
            return true
        }
        guard shouldStart else { return }

        Task { [weak self] in
            defer { self?.isDetecting.withLock { $0 = false } }
            guard let self else { return }

            do {
                var request = DetectHumanRectanglesRequest()
                request.upperBodyOnly = false

                // The rear camera delivers landscape buffers while we hold the
                // phone in portrait, so tell Vision how the image is oriented
                // rather than paying to rotate every frame.
                let observations = try await request.perform(on: pixelBuffer, orientation: .right)

                let found = observations.map { observation in
                    DetectedPerson(
                        id: observation.uuid,
                        // Vision uses a bottom-left origin; flipping gives us
                        // the top-left origin the preview layer expects.
                        boundingBox: observation.boundingBox.verticallyFlipped().cgRect,
                        confidence: observation.confidence
                    )
                }

                await self.publish(self.suppressDuplicates(found))
            } catch {
                await self.publish([])
            }
        }
    }

    /// Vision sometimes reports a smaller box nested inside a larger one for
    /// the same person — common when they're seated rather than standing.
    /// Left alone, each box becomes its own track and the person sprouts a
    /// second balloon.
    nonisolated func suppressDuplicates(_ people: [DetectedPerson]) -> [DetectedPerson] {
        var kept: [DetectedPerson] = []
        for candidate in people.sorted(by: { $0.confidence > $1.confidence }) {
            let alreadyCovered = kept.contains {
                containment(candidate.boundingBox, $0.boundingBox) > 0.6
            }
            if !alreadyCovered { kept.append(candidate) }
        }
        return kept
    }

    /// How much of the *smaller* box lies inside the other. Intersection over
    /// union misses this case: a small box fully inside a big one can score
    /// under 0.3 while being entirely redundant. This scores it 1.0.
    nonisolated private func containment(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = a.intersection(b)
        guard !overlap.isNull else { return 0 }
        let smaller = min(a.width * a.height, b.width * b.height)
        guard smaller > 0 else { return 0 }
        return (overlap.width * overlap.height) / smaller
    }

    private func publish(_ found: [DetectedPerson]) {
        let tracked = tracker.update(with: found)
        profiles.update(for: tracked)
        people = tracked
    }
}
