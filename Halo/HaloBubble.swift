//
//  HaloBubble.swift
//  Halo
//
//  The card a halo actually is: whatever someone chose to put in it.
//

import SwiftUI

struct HaloBubble: View {
    /// Everything is laid out at this width and then scaled as a whole, so a
    /// halo far away and one up close are the same object at different sizes
    /// rather than two different designs.
    static let designWidth: CGFloat = 190

    let profile: HaloProfile
    /// Rough, from apparent size. Omitted when it can't be estimated.
    var distance: Double?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                if let picture {
                    picture
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 116)
                        .clipShape(.rect(cornerRadius: 10))
                } else if let sticker = profile.sticker {
                    Text(sticker)
                        .font(.system(size: 54))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }

                if !profile.name.isEmpty {
                    Text(profile.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                if !profile.message.isEmpty {
                    Text(profile.message)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                if let distance {
                    Text(distance < 10 ? String(format: "%.1f m away", distance)
                                       : String(format: "%.0f m away", distance))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(10)
            .frame(width: Self.designWidth)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(profile.tint.opacity(0.75), lineWidth: 2)
            )

            // A tail so the card reads as belonging to the person below it
            // rather than floating free.
            Triangle()
                .fill(.ultraThinMaterial)
                .frame(width: 14, height: 8)
        }
        .shadow(color: .black.opacity(0.4), radius: 10, y: 3)
    }

    private var picture: Image? {
        guard let data = profile.imageData, let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
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
        HaloBubble(profile: HaloProfile.cast[0], distance: 3.2)
    }
}
