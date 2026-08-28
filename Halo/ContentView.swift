//
//  ContentView.swift
//  Halo
//
//  Created by Karthik Vishnuvajjala on 27/08/26.
//

import SwiftUI

struct ContentView: View {
    @State private var camera = CameraManager()
    @State private var previewHandle = PreviewLayerHandle()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.status {
            case .running:
                CameraPreview(session: camera.session, handle: previewHandle)
                    .overlay { bubbles }
                    .overlay(alignment: .top) { detectionCount }
                    .ignoresSafeArea()

            case .idle:
                ProgressView()
                    .tint(.white)

            case .denied:
                message("Halo needs camera access to see the world around you. "
                        + "Enable it in Settings → Halo → Camera.")

            case .failed(let reason):
                message(reason)
            }
        }
        .statusBarHidden()
        .task { await camera.start() }
    }

    /// A bubble per tracked subject, floating just above their head.
    private var bubbles: some View {
        GeometryReader { geometry in
            ForEach(camera.detector.people) { person in
                if let rect = previewHandle.viewRect(for: person.smoothedBox) {
                    HaloBubble(profile: camera.detector.profile(for: person.id))
                        .fixedSize()
                        .scaleEffect(scale(for: rect), anchor: .bottom)
                        .position(x: bubbleX(above: rect, screenWidth: geometry.size.width),
                                  y: bubbleY(above: rect))
                        // Detection passes land irregularly, so glide between
                        // them instead of snapping to each new position.
                        .animation(.smooth(duration: 0.25), value: rect)
                }
            }
        }
    }

    /// Centred over the person, but pulled back inside the screen so someone
    /// near the edge doesn't get half a bubble.
    private func bubbleX(above rect: CGRect, screenWidth: CGFloat) -> CGFloat {
        let halfBubble = HaloBubble.maxWidth / 2 * scale(for: rect)
        let margin: CGFloat = 8
        return min(max(rect.midX, halfBubble + margin), screenWidth - halfBubble - margin)
    }

    /// The top of the bounding box is roughly the top of the head, so the
    /// bubble sits a little above that rather than at the person's centre.
    /// The gap scales with the person so it looks constant as they approach.
    /// Clamped so someone close to the camera doesn't push it off-screen.
    private func bubbleY(above rect: CGRect) -> CGFloat {
        max(rect.minY - 34 * scale(for: rect), 60)
    }

    /// A nearer person fills more of the frame, so their bubble grows with
    /// them. Clamped at both ends: never unreadably small, never overwhelming.
    private func scale(for rect: CGRect) -> CGFloat {
        /// Roughly a person standing a few metres away, filling half the screen.
        let referenceHeight: CGFloat = 420
        return min(max(rect.height / referenceHeight, 0.7), 1.6)
    }

    private var detectionCount: some View {
        Text("\(camera.detector.people.count) tracked")
            .font(.caption.monospaced())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.5), in: .capsule)
            .padding(.top, 60)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(32)
    }
}

#Preview {
    ContentView()
}
