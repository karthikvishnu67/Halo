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

    /// With this on, halos come from broadcasts that had to be *matched* to a
    /// person — so people who aren't broadcasting get nothing at all. Off, every
    /// detected person gets a profile, which is only useful for testing tracking.
    @AppStorage("simulateRadio") private var simulateRadio = true

    @State private var radio = SimulatedRadio()
    @State private var matcher = PresenceMatcher()

    /// What you are broadcasting, if anything.
    @State private var broadcast = BroadcastController()
    @State private var showComposer = false

    /// Your own halo, kept between launches. Stored as its parts because
    /// @AppStorage holds simple values.
    @AppStorage("myHaloName") private var myName = ""
    @AppStorage("myHaloMessage") private var myMessage = ""
    @AppStorage("myHaloTint") private var myTint = 0

    /// Kept in memory so drawing never touches the disk; written out when it
    /// changes.
    @State private var myImageData: Data? = HaloImageStore.load()

    /// Which tracked person is carrying which broadcast, as decided by the
    /// matcher. Anyone absent from here shows no halo.
    @State private var placements: [Int: HaloProfile] = [:]

    /// Broadcasts heard but not placed on anyone — behind you, through a wall,
    /// or genuinely ambiguous. Shown as a count, never guessed onto a person.
    @State private var unplacedCount = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch camera.status {
            case .running:
                CameraPreview(session: camera.session, handle: previewHandle)
                    .overlay { halos }
                    .overlay(alignment: .top) { status }
                    .overlay(alignment: .topTrailing) { myHaloButton }
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
        .task {
            // Expiry has to be noticed even while nothing else happens, or the
            // app could keep claiming you are visible after you stopped being.
            while !Task.isCancelled {
                broadcast.pruneExpired()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .sheet(isPresented: $showComposer) {
            HaloComposer(draft: myHalo, controller: broadcast)
        }
        .onChange(of: camera.detector.people) { _, people in
            matchBroadcastsToPeople(people)
        }
    }

    /// Runs the whole V2 chain once per detection pass: work out how far away
    /// each person is, hear whatever the radio has to say, and let the matcher
    /// decide which broadcast belongs to whom.
    private func matchBroadcastsToPeople(_ people: [TrackedPerson]) {
        guard simulateRadio, let size = previewHandle.viewSize, size.height > 0 else {
            placements = [:]
            unplacedCount = 0
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let subjects = people.compactMap { person -> PresenceMatcher.Subject? in
            guard let rect = previewHandle.viewRect(for: person.smoothedBox) else { return nil }
            return .init(id: person.id, distance: distanceMetres(of: rect, in: size.height))
        }

        let outcome = matcher.update(subjects: subjects,
                                     presences: radio.presences(for: subjects, at: now),
                                     now: now)

        placements = Dictionary(uniqueKeysWithValues:
            outcome.matched.map { ($0.trackID, $0.presence.profile) })
        unplacedCount = outcome.unplaced.count
    }

    /// A halo for each person we can attribute one to, inside the viewer's radius.
    private var halos: some View {
        GeometryReader { geometry in
            ForEach(camera.detector.people) { person in
                if let profile = profile(for: person.id),
                   let rect = previewHandle.viewRect(for: person.smoothedBox),
                   let head = previewHandle.viewPoint(for: person.displayHead) {
                    let metres = distanceMetres(of: rect, in: geometry.size.height)

                    // An unknown distance still shows a halo: "we can't tell"
                    // must not quietly become "they're too far away".
                    if metres.map({ $0 <= radiusMetres }) ?? true {
                        HaloView(profile: profile,
                                 distance: metres,
                                 headPoint: head,
                                 personHeight: rect.height,
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

    /// Nil means this person gets no halo — either they aren't broadcasting, or
    /// we can't yet tell which broadcast is theirs. Both must look the same from
    /// outside: absent.
    private func profile(for trackID: Int) -> HaloProfile? {
        simulateRadio ? placements[trackID] : camera.detector.profile(for: trackID)
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

    private var status: some View {
        VStack(spacing: 6) {
            Button {
                simulateRadio.toggle()
                placements = [:]
                unplacedCount = 0
            } label: {
                Text(String(format: "%d tracked · %.0f/s · %@",
                            camera.detector.people.count,
                            camera.detector.passesPerSecond,
                            simulateRadio ? "radio" : "all"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.5), in: .capsule)
            }
            .buttonStyle(.plain)

            // Heard, but not placed on anyone. Saying so is honest and builds
            // anticipation; guessing would put someone's message over a
            // stranger's head.
            if simulateRadio && unplacedCount > 0 {
                Text("◍ \(unplacedCount) nearby")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.35), in: .capsule)
            }
        }
        .padding(.top, 60)
    }

    private var myHalo: Binding<HaloDraft> {
        Binding(
            get: {
                HaloDraft(name: myName, message: myMessage,
                          tintIndex: myTint, imageData: myImageData)
            },
            set: { draft in
                let clamped = draft.clamped
                myName = clamped.name
                myMessage = clamped.message
                myTint = clamped.tintIndex
                if clamped.imageData != myImageData {
                    myImageData = clamped.imageData
                    HaloImageStore.save(clamped.imageData)
                }
            }
        )
    }

    /// Your own halo, and whether it is currently visible to anyone. Knowing
    /// that at a glance is a privacy commitment, not a convenience — so the
    /// countdown ticks rather than sitting there stale.
    private var myHaloButton: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let broadcasting = broadcast.isBroadcasting(at: context.date)

            Button {
                showComposer = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: broadcasting
                          ? "dot.radiowaves.left.and.right"
                          : "person.crop.circle.dashed")
                    if broadcasting {
                        Text(remainingLabel(at: context.date))
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(broadcasting ? .black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(broadcasting ? AnyShapeStyle(.green.opacity(0.85))
                                         : AnyShapeStyle(.black.opacity(0.5)),
                            in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 58)
        .padding(.trailing, 16)
    }

    private func remainingLabel(at moment: Date) -> String {
        let minutes = Int(broadcast.remaining(at: moment)) / 60
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return minutes > 0 ? "\(minutes)m" : "<1m"
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
