//
//  PersonDetector.swift
//  Halo
//
//  Finds people in camera frames and works out where their heads are.
//

import CoreVideo
import Foundation
import Observation
import os
import Vision

/// One person Vision found in a single frame.
///
/// The `id` is Vision's per-observation UUID: it is *not* stable across frames,
/// so it must not be treated as a lasting identity. Frame-to-frame identity
/// comes from `PersonTracker`.
struct DetectedPerson: Identifiable {
    let id: UUID
    /// Normalized 0-1, top-left origin — i.e. AVFoundation's "metadata output"
    /// space, which the preview layer can convert into view coordinates.
    let boundingBox: CGRect
    /// Roughly the crown of the head, in the same space. Derived from joints
    /// rather than from the top of the box, so it survives a person sitting,
    /// leaning or lying down.
    let headPoint: CGPoint
    let confidence: Float
}

@MainActor
@Observable
final class PersonDetector {

    /// Subjects with identity that persists across frames.
    private(set) var people: [TrackedPerson] = []

    /// Detection passes completed per second — a cheap way to see what a
    /// heavier Vision request costs us.
    private(set) var passesPerSecond: Double = 0

    @ObservationIgnored private let tracker = PersonTracker()
    @ObservationIgnored private let profiles = ProfileDirectory()
    @ObservationIgnored private var lastPassAt: Date?

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
                let request = DetectHumanBodyPoseRequest()

                // The rear camera delivers landscape buffers while we hold the
                // phone in portrait, so tell Vision how the image is oriented
                // rather than paying to rotate every frame.
                let observations = try await request.perform(on: pixelBuffer, orientation: .right)

                let found = observations.compactMap(Self.person(from:))
                await self.publish(self.suppressDuplicates(found))
            } catch {
                await self.publish([])
            }
        }
    }

    /// Turns a skeleton into a box to track and a head to hang a halo from.
    nonisolated private static func person(from observation: HumanBodyPoseObservation) -> DetectedPerson? {
        let joints = observation.allJoints().filter { $0.value.confidence > 0.25 }
        guard joints.count >= 3 else { return nil }

        // Vision's y grows upwards. Flip once here so every calculation below
        // matches the screen, where y grows downwards.
        func joint(_ name: HumanBodyPoseObservation.JointName) -> CGPoint? {
            joints[name].map { CGPoint(x: $0.location.x, y: 1 - $0.location.y) }
        }

        let all = joints.values.map { CGPoint(x: $0.location.x, y: 1 - $0.location.y) }
        let xs = all.map(\.x), ys = all.map(\.y)
        let box = CGRect(x: xs.min()!, y: ys.min()!,
                         width: xs.max()! - xs.min()!,
                         height: ys.max()! - ys.min()!)

        let face = [joint(.nose), joint(.leftEye), joint(.rightEye),
                    joint(.leftEar), joint(.rightEar)].compactMap { $0 }
        let shoulders = [joint(.leftShoulder), joint(.rightShoulder)].compactMap { $0 }

        let head: CGPoint
        if let eyes = average(face) {
            if let shoulder = average(shoulders), shoulder.y > eyes.y {
                // The crown sits above the eyes by roughly two thirds of the
                // gap down to the shoulders.
                head = CGPoint(x: eyes.x, y: eyes.y - 0.65 * (shoulder.y - eyes.y))
            } else {
                head = CGPoint(x: eyes.x, y: eyes.y - 0.04)
            }
        } else if let shoulder = average(shoulders) {
            // Facing away, or the head is out of frame: estimate from how wide
            // the shoulders are, which stands in for how close they are.
            let width = shoulders.count == 2 ? abs(shoulders[0].x - shoulders[1].x) : 0.05
            head = CGPoint(x: shoulder.x, y: shoulder.y - max(width, 0.03) * 1.1)
        } else {
            head = CGPoint(x: box.midX, y: box.minY)
        }

        return DetectedPerson(id: observation.uuid,
                              boundingBox: box,
                              headPoint: head,
                              confidence: observation.confidence)
    }

    nonisolated private static func average(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let count = CGFloat(points.count)
        return CGPoint(x: points.map(\.x).reduce(0, +) / count,
                       y: points.map(\.y).reduce(0, +) / count)
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
        let now = Date()
        if let last = lastPassAt {
            let rate = 1 / max(now.timeIntervalSince(last), 0.001)
            // Smoothed, or the number is unreadable.
            passesPerSecond = passesPerSecond == 0 ? rate : passesPerSecond * 0.8 + rate * 0.2
        }
        lastPassAt = now

        let tracked = tracker.update(with: found, at: ProcessInfo.processInfo.systemUptime)
        profiles.update(for: tracked)
        people = tracked
    }
}
