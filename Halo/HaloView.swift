//
//  HaloView.swift
//  Halo
//
//  A person's halo: a balloon tethered to the top of their head.
//

import SwiftUI

/// The resting state is a small balloon — glanceable, and a crowd of them
/// stays readable. Tapping inflates it into the person's actual message, so
/// detail is deferred until you attend to someone rather than hidden.
struct HaloView: View {
    let profile: HaloProfile
    let distance: Double?
    /// Top of the person's head, in view coordinates.
    let headPoint: CGPoint
    /// The person's on-screen height, which is what everything scales from:
    /// a nearer person is taller, so their halo is bigger and floats higher.
    let personHeight: CGFloat
    /// Grows with the person, used for the opened card.
    let scale: CGFloat
    let isOpen: Bool
    let screenWidth: CGFloat
    let onTap: () -> Void

    /// Proportional to the person, like a balloon on a string of fixed length
    /// held by someone walking towards you: both grow as they approach.
    private var balloonSize: CGFloat { min(max(personHeight * 0.10, 14), 34) }

    /// Someone close fills the frame, leaving no room above their head. Rather
    /// than pinning the balloon to the top of the screen — which reads as
    /// belonging to nobody — the string simply shortens.
    private var tetherLength: CGFloat {
        let wanted = min(max(personHeight * 0.28, 22), 90)
        let available = max(headPoint.y - balloonSize - 14, 0)
        return min(wanted, available)
    }

    var body: some View {
        // An opened card can be pushed inward at the screen edge, so the
        // string leans across to wherever it actually sits — like a balloon
        // drifting — instead of pointing at empty space.
        let anchorX = isOpen
            ? clampedX(headPoint.x, halfWidth: HaloBubble.maxWidth / 2 * scale)
            : headPoint.x
        let anchor = CGPoint(x: anchorX, y: headPoint.y - tetherLength)

        ZStack {
            tether(to: anchor)

            if isOpen {
                HaloBubble(profile: profile, distance: distance)
                    .fixedSize()
                    .scaleEffect(scale, anchor: .bottom)
                    .position(x: anchor.x, y: anchor.y - 28 * scale)
                    .onTapGesture(perform: onTap)
            } else {
                balloon
                    .position(anchor)
                    .onTapGesture(perform: onTap)
            }
        }
    }

    /// The line to the head is what makes a halo unmistakably *someone's*,
    /// even when several overlap.
    private func tether(to anchor: CGPoint) -> some View {
        let line = Path { path in
            path.move(to: headPoint)
            path.addLine(to: anchor)
        }
        // Drawn twice: a dark stroke underneath keeps the string visible
        // against a bright street, where a thin white line disappears.
        return ZStack {
            line.stroke(.black.opacity(0.35),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            line.stroke(.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
        }
    }

    private var balloon: some View {
        Circle()
            .fill(profile.tint.opacity(0.75))
            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
            .frame(width: balloonSize, height: balloonSize)
            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
            // A 22pt dot is hard to hit; keep the tap target finger-sized.
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    private func clampedX(_ x: CGFloat, halfWidth: CGFloat) -> CGFloat {
        min(max(x, halfWidth + 8), screenWidth - halfWidth - 8)
    }
}
