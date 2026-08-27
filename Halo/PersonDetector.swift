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

    private(set) var people: [DetectedPerson] = []

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

                await self.publish(found)
            } catch {
                await self.publish([])
            }
        }
    }

    private func publish(_ found: [DetectedPerson]) {
        people = found
    }
}
