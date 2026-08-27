# Halo

An experimental iOS side project: point a phone camera at a person, and see an optional
digital "halo" — a small bubble of information they chose to broadcast — floating above them.

```text
        💬
  "Open to meeting
     new people :)"
        👤
```

The long-term north star is AR glasses where digital presence feels like another layer of
reality. **That vision must not leak into what we build this week.** The single most important
instruction in this file is: *keep the current version small.*

## Status: V0 → starting V1.1

The repo is still the default SwiftUI template ("Hello, world!"). Nothing product-specific
has been written yet.

```text
Halo/
├── Halo.xcodeproj/
└── Halo/
    ├── HaloApp.swift      # @main App, WindowGroup { ContentView() }
    ├── ContentView.swift  # default template view
    └── Assets.xcassets/
```

**Immediate objective: get the rear camera feed rendering full-screen in the app.**
Not detection. Not tracking. Not bubbles. Just the camera.

## Roadmap

Conceptual, not rigid release numbers.

| Version | Proves |
|---|---|
| V0 | Xcode + Swift + Git + device deployment work *(done)* |
| **V1** | **Camera → person detection → tracking → bubble attached to a person** |
| V1.5 | Multiple people with simulated local profiles |
| V2 | Real users, opt-in nearby presence, some networking |
| V2.5 | Better spatial positioning and interaction |
| V3 | Dedicated wearable / pin as a presence beacon |
| V4 | AR glasses / spatial computing |

### V1 milestones — do these one at a time

- **V1.1 Camera** — rear camera fills the screen, permission handled. Nothing else.
- **V1.2 Detection** — detect people in the feed; visualizing raw bounding boxes is fine.
- **V1.3 Tracking** — follow a detected person across frames without re-detecting blindly
  every frame. Test: walking left/right, toward/away, partial occlusion, multiple people,
  camera movement.
- **V1.4 Head position** — derive a point above the head from the box; the bubble is *not*
  anchored at the person's center.
- **V1.5 Bubble UI** — one simple, readable SwiftUI bubble. No visual complexity.
- **V1.6 Stability** — smooth/filter the position. Goal is "the bubble belongs to the
  person", not mathematically perfect tracking.
- **V1.7 Multiple people** — independent bubbles per tracked subject.

### V1 explicitly does NOT need

Accounts, auth, a backend, networking, Bluetooth, custom ML models, a social graph, dating
features, AR glasses, a physical pin, persistent identity, facial recognition, cloud CV, or
production privacy infrastructure. V1 is a computer-vision + tracking + UI prototype.

Identity in V1 is a hardcoded local profile ("Maya — Open to meeting people"). The chain we
are proving is: physical person → detected visual subject → digital state → bubble.

## Technical approach

Prefer Apple's native frameworks; add nothing else unless it solves a real problem.

- **AVFoundation** — camera capture
- **Vision** — person detection and tracking
- **SwiftUI** — app and overlay UI
- **ARKit** — *not yet.* Do not reach for it just because the eventual product is AR.

V1 works in **2D screen space**. The question is "where is this person in the camera image?",
not "where are they in the room in 3D?"

```text
Camera image + SwiftUI overlay = Halo prototype
```

Detection alone jitters. A tracking layer is required for the bubble to feel attached.

**Verify APIs before committing to them.** iOS has both the legacy `VN*` Vision request
classes and the newer Swift Vision API; availability and behaviour differ by iOS version.
Check what actually exists on the deployment target rather than writing from memory.

## Project facts

- Bundle id `karthik.Halo`, team `PZ2FYW6KHL`, Swift 5, iPhone + iPad targets.
- **Deployment target is iOS 26.2** and the SDK is Xcode 26.3 / iOS 26.2. The test iPhone must
  be on iOS 26.2+. Lower this if that turns out to be inconvenient.
- `GENERATE_INFOPLIST_FILE = YES` — there is no Info.plist file in the repo. The camera
  permission string is added as an `INFOPLIST_KEY_NSCameraUsageDescription` build setting
  (or by adding a real Info.plist), not by editing a file that doesn't exist.
- The camera does not work in the Simulator. V1 must be tested on the physical iPhone.
- Remote: `github.com/karthikvishnu67/Halo`.

## Privacy principles (architectural, not features to bolt on later)

Halo is **opt-in**. Someone must never become a publicly identifiable Halo user just because
another person pointed a camera at them. The system's question is *"is this person
voluntarily broadcasting a presence?"* — never *"who is this stranger?"* That distinction is
why we avoid facial recognition as a shortcut to identity, even when it would be easier.

Users control whether they are visible, what is shown, and when it expires. Presence can be
ephemeral ("free for coffee", "anyone going to the hackathon?"). Process video on-device;
don't store footage. Make it obvious when a user's own Halo is active.

The design problem underneath all of it: how do we add a digital social layer without turning
the world into a wall of notification bubbles?

## How to work on this repo

This is a learning/experimentation project by a student, not a production startup.
Working prototypes and understandable architecture beat polish and abstraction.

- **Do not build ahead of the roadmap.** Implement the smallest useful change for the current
  milestone. If a task feels like it spans three milestones, split it.
- **Explain before large changes.** Inspect the code, describe the approach, name the files
  that will change and the tradeoffs, and wait for approval when the change is architectural.
  Karthik wants to understand what is being built — implementations should be explainable.
- No premature MVVM / clean-architecture scaffolding. Add structure when the code needs it.
- No new dependencies without a real justification.
- Don't rewrite working code, and don't slip in unrelated changes.
- Build (and test on device where possible) after changes; show real errors rather than
  claiming success.

### Git

Commit meaningful milestones separately — camera pipeline, person detection, tracking, bubble
overlay, smoothing, multiple people. Avoid giant mixed commits. Preserve a known-good state
before an architectural change.
