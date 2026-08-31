//
//  HaloView.swift
//  Halo
//
//  A person's halo: a card on a string, tethered to the top of their head.
//

import SwiftUI

/// One object at two sizes rather than two designs. A halo's size follows the
/// person's apparent size, so distance does the work of keeping a crowd
/// glanceable: someone far away is a small shape you can see but not read,
/// someone close is a card big enough to hold a picture. Tapping brings a
/// distant one up to a readable size, which is the "detail on attention" part
/// of the design.
struct HaloView: View {
    let profile: HaloProfile
    let distance: Double?
    /// Top of the person's head, in view coordinates.
    let headPoint: CGPoint
    /// The person's on-screen height, which everything scales from.
    let personHeight: CGFloat
    let isOpen: Bool
    let screenWidth: CGFloat
    let onTap: () -> Void

    /// The card's real height, measured rather than assumed. Guessing it left
    /// a visible gap between the card's tail and the top of the string, since
    /// a card holding a picture is a very different height from one holding a
    /// line of text.
    @State private var measuredHeight: CGFloat = 120

    /// How wide the card is drawn. A halo is a good fraction of its owner —
    /// big enough to carry a meme when they're near you.
    private var cardWidth: CGFloat {
        let perspective = min(max(personHeight * 0.55, 52), 210)
        // Opened, it comes up to a size worth reading even if its owner is
        // right across the room.
        return isOpen ? max(perspective, 175) : perspective
    }

    private var cardScale: CGFloat {
        cardWidth / HaloBubble.designWidth
    }

    private var cardHeight: CGFloat {
        measuredHeight * cardScale
    }

    /// Proportional to the person, like a balloon on a string of fixed length:
    /// both grow as they walk towards you. Shortened when someone is close
    /// enough that there is no room above their head, so the halo never ends up
    /// pinned to the top of the screen looking like it belongs to nobody.
    private var tetherLength: CGFloat {
        let wanted = min(max(personHeight * 0.22, 18), 70)
        let available = max(headPoint.y - cardHeight - 12, 0)
        return min(wanted, available)
    }

    var body: some View {
        let halfCard = cardWidth / 2
        let anchorX = min(max(headPoint.x, halfCard + 8), screenWidth - halfCard - 8)
        let anchor = CGPoint(x: anchorX, y: headPoint.y - tetherLength)

        ZStack {
            tether(to: anchor)

            HaloBubble(profile: profile, distance: isOpen ? distance : nil)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    measuredHeight = height
                }
                .scaleEffect(cardScale, anchor: .bottom)
                .position(x: anchor.x, y: anchor.y - cardHeight / 2)
                .onTapGesture(perform: onTap)
        }
    }

    /// The line to the head is what makes a halo unmistakably *someone's*,
    /// even when several overlap. It leans across when a card had to be pulled
    /// in from the screen edge, like a balloon drifting on its string.
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
}
