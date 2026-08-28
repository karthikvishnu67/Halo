//
//  HaloBubble.swift
//  Halo
//
//  The digital layer a person carries: a small message floating above them.
//

import SwiftUI

struct HaloBubble: View {
    /// Bounded so a long message can't stretch off-screen, and so the overlay
    /// knows how far from the edge a bubble must stay.
    static let maxWidth: CGFloat = 190

    let profile: HaloProfile

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 1) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(profile.message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: Self.maxWidth)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            )

            // A small tail so the bubble reads as belonging to the person
            // below it rather than floating free.
            Triangle()
                .fill(.ultraThinMaterial)
                .frame(width: 12, height: 7)
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.gray
        HaloBubble(profile: HaloProfile.cast[0])
    }
}
