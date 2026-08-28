//
//  HaloBubble.swift
//  Halo
//
//  The digital layer a person carries: a small message floating above them.
//

import SwiftUI

struct HaloBubble: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: .capsule)
                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))

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
        HaloBubble(text: "Hello from Halo 👋")
    }
}
