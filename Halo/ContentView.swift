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

    /// The viewer's own dial: how far away they care about. Their filter,
    /// their call — see the design notes in CLAUDE.md.
    @AppStorage("haloRadiusMetres") private var radiusMetres: Double = 12

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.status {
            case .running:
                CameraPreview(session: camera.session, handle: previewHandle)
                    .overlay { halos }
                    .overlay(alignment: .top) { detectionCount }
                    .overlay(alignment: .bottom) { radiusDial }
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

    /// One halo per tracked subject, inside the viewer's chosen radius.
    private var halos: some View {
        GeometryReader { geometry in
            ForEach(camera.detector.people) { person in
                if let rect = previewHandle.viewRect(for: person.smoothedBox),
                   let head = previewHandle.viewPoint(for: person.displayHead) {
                    let metres = distanceMetres(of: rect, in: geometry.size.height)

                    // An unknown distance still shows a halo: "we can't tell"
                    // must not quietly become "they're too far away".
                    if metres.map({ $0 <= radiusMetres }) ?? true {
                        HaloView(profile: camera.detector.profile(for: person.id),
                                 distance: metres,
                                 headPoint: head,
                                 personHeight: rect.height,
                                 scale: scale(for: rect),
                                 isOpen: openedTrackID == person.id,
                                 screenWidth: geometry.size.width,
                                 onTap: { toggle(person.id) })
                            // Just long enough to bridge the gap between
                            // detection passes (15-30 a second). Longer, and
                            // the halo is always animating towards a position
                            // that has already been superseded — which is what
                            // reads as lag.
                            .animation(.smooth(duration: 0.1), value: rect)
                            .animation(.smooth(duration: 0.1), value: head)
                    }
                }
            }
        }
    }

    /// Someone's apparent height gives a rough distance. Nil means we couldn't
    /// tell — a seated person, or someone cut off by the frame — which must
    /// stay distinct from "they are far away".
    private func distanceMetres(of rect: CGRect, in screenHeight: CGFloat) -> Double? {
        guard camera.fieldOfView > 0, screenHeight > 0 else { return nil }
        let fraction = Double(rect.height / screenHeight)
        guard let metres = DistanceEstimate.metres(heightFraction: fraction,
                                                   fieldOfView: camera.fieldOfView),
              DistanceEstimate.plausibleRange.contains(metres) else { return nil }
        return metres
    }

    /// The viewer's radius. Deliberately theirs to set, not ours to decide.
    private var radiusDial: some View {
        VStack(spacing: 4) {
            Text(radiusMetres >= 30 ? "everyone in view"
                                    : String(format: "within %.0f m", radiusMetres))
                .font(.caption.monospaced())
                .foregroundStyle(.white)
            Slider(value: $radiusMetres, in: 2...30)
                .tint(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.4), in: .rect(cornerRadius: 14))
        .padding(.horizontal, 40)
        .padding(.bottom, 40)
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
        Text(String(format: "%d tracked · %.0f/s",
                    camera.detector.people.count, camera.detector.passesPerSecond))
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
