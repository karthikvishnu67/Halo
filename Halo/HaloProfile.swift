//
//  HaloProfile.swift
//  Halo
//
//  Stand-in identities until real opted-in users exist.
//

import SwiftUI

/// What a person is broadcasting: who they are and what they're signalling.
///
/// Content is deliberately unconstrained — a name, a status, a song, a joke.
/// The only limit is size: a balloon has to stay balloon-sized.
struct HaloProfile {
    let name: String
    let message: String
    /// Colours the balloon, so several people are distinguishable at a glance.
    /// Per-person decoration, not a category the app assigns.
    let tint: Color

    /// Something bigger than words: a meme, album art, a photo. A halo is
    /// allowed to be mostly picture — the size limit is on the balloon, not on
    /// what kind of thing goes in it.
    var imageData: Data?

    /// A stand-in for a picture until there is one: a large glyph or emoji.
    var sticker: String?

    /// A small fake cast, so multiple people on screen are distinguishable.
    ///
    /// Real profiles arrive in V2, when a person's device broadcasts its own
    /// presence. Until then this is theatre: the app has no idea who anyone is.
    static let cast: [HaloProfile] = [
        HaloProfile(name: "Vegeta", message: "checking power levels", tint: .orange,
                    imageData: DemoArtwork.overNineThousand),
        HaloProfile(name: "Arjun", message: "Looking for a chess game", tint: .orange, sticker: "♟️"),
        HaloProfile(name: "Priya", message: "Open to meeting people", tint: .mint),
        HaloProfile(name: "Rohan", message: "Anyone going to the hackathon?", tint: .yellow),
        HaloProfile(name: "Ananya", message: "Free for coffee", tint: .cyan, sticker: "☕️"),
        HaloProfile(name: "Dev", message: "AI • Chess • Photography", tint: .purple),
        HaloProfile(name: "Sara", message: "Just arrived", tint: .green),
        HaloProfile(name: "Ishaan", message: "Ask me about music", tint: .blue, sticker: "🎧"),
    ]

}

/// Hands each tracked subject a profile, and keeps it while they stay on screen.
///
/// Assigning by `id % cast.count` was simpler but gave two people on screen the
/// same name once ids passed the size of the cast. This hands out profiles
/// nobody else currently visible is using instead.
@MainActor
final class ProfileDirectory {

    private var assigned: [Int: Int] = [:]   // track id -> index into the cast

    /// Called once per detection pass, before the UI reads anything.
    func update(for people: [TrackedPerson]) {
        // Subjects who are gone release their profile for reuse.
        let live = Set(people.map(\.id))
        assigned = assigned.filter { live.contains($0.key) }

        for person in people where assigned[person.id] == nil {
            let taken = Set(assigned.values)
            let free = (0..<HaloProfile.cast.count).first { !taken.contains($0) }
            // With more people on screen than cast members, duplicates are
            // unavoidable — fall back to wrapping around.
            assigned[person.id] = free ?? (person.id % HaloProfile.cast.count)
        }
    }

    func profile(for id: Int) -> HaloProfile {
        HaloProfile.cast[assigned[id] ?? 0]
    }
}
