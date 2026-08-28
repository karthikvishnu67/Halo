//
//  HaloPresence.swift
//  Halo
//
//  Someone nearby who is broadcasting a halo.
//

/// A broadcast heard over the radio — not yet attached to anyone on screen.
///
/// The camera can only ever answer "where is a person". Whether that person
/// runs Halo arrives separately, through this. Joining the two is what
/// `PresenceMatcher` does.
struct HaloPresence: Identifiable {
    /// A rotating temporary id from the radio. Deliberately *not* stable over
    /// time: it identifies a broadcast, never a person, so nobody can log a
    /// beacon today and recognise the same human tomorrow.
    let id: String

    /// What they chose to broadcast.
    let profile: HaloProfile

    /// Metres, inferred from signal strength. Very rough — human bodies absorb
    /// radio, so someone facing away can read twice as far as they are. Only
    /// really trustworthy as a trend, which is why the matcher leans on how
    /// this changes rather than on any single reading.
    let estimatedDistance: Double
}
