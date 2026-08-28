//
//  DistanceEstimate.swift
//  Halo
//
//  Turns how big someone looks into roughly how far away they are.
//

import Foundation

/// A person's apparent size is an inverse distance sensor: someone twice as far
/// away looks half as tall. That only works because we can assume how big a
/// human is — which is exactly the assumption that makes it approximate.
enum DistanceEstimate {

    /// What a pose box actually spans. Vision's joints run from around the eyes
    /// down to the ankles, so the box is short of a person's full height, and
    /// this is the working figure rather than 1.7m.
    static let assumedBodySpan: Double = 1.30

    /// - Parameters:
    ///   - heightFraction: how much of the frame's height the person occupies, 0-1.
    ///   - fieldOfView: the camera's field of view along that axis, in degrees.
    /// - Returns: distance in metres, or nil if the inputs can't give an answer.
    static func metres(heightFraction: Double,
                       fieldOfView: Double,
                       bodySpan: Double = assumedBodySpan) -> Double? {
        guard heightFraction > 0.001, fieldOfView > 1, fieldOfView < 179 else { return nil }

        // Half the frame covers tan(fov/2) at unit distance. A person filling
        // `heightFraction` of the frame therefore sits at:
        //
        //     distance = bodySpan / (2 · heightFraction · tan(fov / 2))
        let halfAngle = (fieldOfView / 2) * .pi / 180
        return bodySpan / (2 * heightFraction * tan(halfAngle))
    }

    /// Sitting, crouching or being cut off by the frame all shrink someone's
    /// apparent height, so anything beyond this is not worth reporting.
    static let plausibleRange: ClosedRange<Double> = 0.4...40
}
