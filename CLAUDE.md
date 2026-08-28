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

## Status: V1.1–V1.6 done, V1.7 next

The core V1 loop works on device: rear camera → Vision person detection →
IoU-based tracking with stable ids → a smoothed bubble floating above each
person's head, scaling with their distance.

```text
Halo/
├── Halo.xcodeproj/
└── Halo/
    ├── HaloApp.swift         # @main App
    ├── ContentView.swift     # full-screen preview + bubble overlay
    ├── CameraManager.swift   # AVCaptureSession: permission, config, start/stop
    ├── CameraPreview.swift   # AVCaptureVideoPreviewLayer in SwiftUI + coordinate conversion
    ├── FrameForwarder.swift  # NSObject delegate adapter for video frames
    ├── PersonDetector.swift  # Vision body pose -> box + head point, one request in flight
    ├── PersonTracker.swift   # frame-to-frame identity, adaptive smoothing, prediction
    ├── HaloProfile.swift     # fake cast + collision-free profile assignment
    ├── HaloView.swift        # balloon, tether, open/closed state
    ├── HaloBubble.swift      # the opened message card
    └── Assets.xcassets/
```

V1 is complete. Halos are now balloons on a string, tethered to the head Vision
reports, opening into the person's message on tap.

**Next:** distance estimation from apparent size (the viewer's radius dial), and
letting the user set their own halo instead of a hardcoded cast.

### Hard-won details worth not rediscovering

- **Coordinate conversion.** Vision reports upright portrait rects; AVFoundation's
  metadata output space is the sensor's *landscape* space, and
  `layerRectConverted(fromMetadataOutputRect:)` rotates into portrait itself. Rects
  must be rotated back into sensor space before that call or everything is rotated
  twice. See `PreviewLayerHandle.viewRect(for:)`.
- **`@Observable` rewrites stored properties** into tracked computed ones, which
  silently defeats `nonisolated(unsafe)`. Anything the UI doesn't read needs
  `@ObservationIgnored`.
- **The project defaults every type to `@MainActor`** (`SWIFT_DEFAULT_ACTOR_ISOLATION`),
  so AVFoundation delegates called on background queues must be explicitly
  `nonisolated`.
- **Smoothing adapts to speed, and that needs a filtered velocity *vector*.** One
  fixed constant cannot both steady a still person and keep up with a walking one.
  Filtering the step *size* fails: jitter alternates direction, so a shivering
  detection reads as a sprint and the filter opens right up. Filtering the vector
  cancels jitter and accumulates real movement. With prediction on top, measured
  0.0029 twitch standing still and 0.0027 lag walking — better than the fixed
  filter managed at either.
- **Head position must come from joints, not the box.** The top-centre of a
  bounding box is only the head for someone standing upright; for a person
  reclining on a sofa it is a point in mid-air. `DetectHumanBodyPoseRequest`
  gives real head joints, and ran *faster* in practice (15-30 passes/s).
- **Detectors report nested duplicate boxes** for one person, especially when
  seated. IoU misses these (a real pair scored 0.284, under the match threshold);
  suppress on how much of the smaller box lies inside the larger.
- **Detection is unreliable in dim rooms** regardless of request type — verified
  by running both Vision requests over captured frames.

## Roadmap

Conceptual, not rigid release numbers.

| Version | Proves |
|---|---|
| V0 | Xcode + Swift + Git + device deployment work *(done)* |
| **V1** | **Camera → person detection → tracking → bubble attached to a person** *(1.1–1.6 done)* |
| V1.5 | Multiple people with simulated local profiles |
| V2 | Real users, opt-in nearby presence, some networking |
| V2.5 | Better spatial positioning and interaction |
| V3 | Dedicated wearable / pin as a presence beacon |
| V4 | AR glasses / spatial computing |

### The design, and why — decided deliberately

The inspiration is a Finnish grocery store that hands out pink carts to single
shoppers. One bit of information, opt-in, anonymous, ephemeral, reversible — and
a store with twenty pink carts is *not* cluttered, because it reads at a glance.
Everything below follows from taking that seriously.

**What a halo is**

- A **signal, not a profile.** "Dancing Queen playing" or "free for coffee" beats
  a bio. Signals describe a moment, and are ephemeral by default.
- **Content is never restricted.** Text, a song, a joke, a meme, "CS • photography
  • startups" if that is what someone wants. Instagram Notes, not a dating profile.
  The only limit is **size** — a balloon must stay balloon-sized. That constraint
  is what makes the medium work, and it is a limit on format, never on subject.

**Visual language**

- A **balloon on a string, tethered to the top of the head** — the cartoon
  thought-cloud. The tether is not decoration: it makes ownership unambiguous when
  several halos overlap.
- **Physically plausible.** Size and string length scale with the person, so a
  halo behaves like an object hanging above them rather than UI pasted on glass.
  This is what makes it read as attached; it is also the same behaviour that
  carries over to AR glasses.

**The attention model — this is how clutter is solved**

- **Balloon by default, message on attention.** Tap opens one halo; in glasses
  this becomes gaze. One open at a time.
- Detail is **deferred, never denied.** Nobody in range is hidden. A crowd of
  balloons is glanceable where a crowd of text cards is not.
- A radius filters the *street*; deferring detail handles the *room*. Both are
  needed: with fifteen opted-in people inside a 10m radius at a hackathon, a
  radius alone still produces a wall of text.

Three dials, none of which overrides a person:

| Dial | Controlled by |
|---|---|
| What I broadcast | the sender — unrestricted |
| How far away I care about | the viewer — their radius |
| How much renders at once | attention — look at someone, their halo opens |

**Consent and etiquette**

- **Opt-in only.** Someone without Halo is not blurred or anonymised, they are
  *absent* from the system.
- The camera answers **"where is a person"**, never "who is this person". No
  facial recognition, as an architectural commitment.
- **No read receipts.** Nobody is told their halo was looked at. A glance should
  stay a glance rather than become a staring contest.
- **Halo carries no messages.** Seeing a signal should make you walk over and
  speak. This is a product decision first, and it also keeps the project clear of
  messaging, blocking, moderation and abuse reporting.
- **Not always on.** Halos appear when you open the app (or accept in glasses),
  not permanently in your peripheral vision.
- **You can see your own halo** by looking up — how you know what you are
  broadcasting.
- **Halos never demand attention.** No pings, no flashes. Only what you are facing
  is visible, so field of view is a natural rate limiter and nobody can scan a
  room from behind.
- **Seamless.** Halos fade in and out as people enter and leave range. If it feels
  like an app updating a list, it is wrong.

### Open questions — not yet decided

- **Memory across a glance away.** Turn your head and back: is that the same
  person? Today the track dies and the profile changes. In AR this is world
  anchoring — remembering a *location*, which is memory the privacy principles
  permit, unlike remembering a face.
- **Where real distance comes from.** Apparent size is the V1 approximation. Later:
  BLE signal strength (noisy, no direction), UWB (precise distance *and*
  direction, needs BLE to discover first), or depth sensing.
- **The association problem — the genuinely unsolved part.** The camera yields
  bodies on screen; the radio yields opted-in users nearby. Matching them is hard
  when two users are the same distance away. Options: correlate how distances
  change over time, use UWB direction, or ask the viewer to confirm.
- **Expiry semantics** for ephemeral signals: minutes, an event, leaving a place.

### V1 milestones — do these one at a time

- ~~**V1.1 Camera**~~ — done.
- ~~**V1.2 Detection**~~ — done, `DetectHumanRectanglesRequest`.
- ~~**V1.3 Tracking**~~ — done, IoU association with a 2-pass visible window and an
  8-pass retirement window. Not yet stress-tested on people crossing paths, where
  geometry-only matching is expected to swap ids; the fix would be appearance
  (`TrackObjectRequest`) if it turns out to matter.
- ~~**V1.4 Head position**~~ — done, anchored to the top of the box.
- ~~**V1.5 Bubble UI**~~ — done.
- ~~**V1.6 Stability**~~ — done, exponential smoothing plus SwiftUI animation.
- **V1.7 Multiple people** — the tracker and UI already handle N subjects; needs
  verifying with several people in frame.

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
