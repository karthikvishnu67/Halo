//
//  HaloPresence.swift
//  Halo
//
//  Someone nearby who is broadcasting a halo.
//

import Foundation

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

    /// Metres, inferred from signal strength — before any filtering. Very
    /// rough, and biased *long*: obstruction weakens a signal, which reads as
    /// further away, while nothing makes someone read closer than they are.
    /// `RadioDistanceFilter` exploits that asymmetry.
    let rawDistance: Double

    /// When this reading arrived, on a monotonic clock. Readings arrive
    /// irregularly — many times a second from a foregrounded phone, perhaps
    /// once a second from one advertising in someone's pocket — so the matcher
    /// works in real time rather than counting updates.
    let heardAt: TimeInterval
}
