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
    /// Only one halo is open at a time — attention is the point.
    @State private var openedTrackID: Int?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.status {
            case .running:
                CameraPreview(session: camera.session, handle: previewHandle)
                    .overlay { halos }
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

    /// One halo per tracked subject.
    private var halos: some View {
        GeometryReader { geometry in
            ForEach(camera.detector.people) { person in
                if let rect = previewHandle.viewRect(for: person.smoothedBox) {
                    HaloView(profile: camera.detector.profile(for: person.id),
                             headPoint: CGPoint(x: rect.midX, y: rect.minY),
                             personHeight: rect.height,
                             scale: scale(for: rect),
                             isOpen: openedTrackID == person.id,
                             screenWidth: geometry.size.width,
                             onTap: { toggle(person.id) })
                        // Detection passes land irregularly, so glide between
                        // them instead of snapping to each new position.
                        .animation(.smooth(duration: 0.25), value: rect)
                }
            }
        }
    }

    private func toggle(_ id: Int) {
        openedTrackID = (openedTrackID == id) ? nil : id
    }

    /// A nearer person fills more of the frame, so their halo grows with them.
    /// Clamped at both ends: never unreadably small, never overwhelming.
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
