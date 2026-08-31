//
//  HaloDraft.swift
//  Halo
//
//  What you are about to broadcast, before you commit to it.
//

import SwiftUI

/// Your own halo, as you compose it.
///
/// Content is deliberately unconstrained — a name, a status, a song, a joke,
/// a list of interests. The *only* limit is size, because a balloon has to stay
/// balloon-sized to stay glanceable in a crowd. That is a limit on format, and
/// never on subject.
struct HaloDraft: Equatable {

    /// Roughly a name's worth.
    static let nameLimit = 20

    /// About the length of an Instagram note: a sentence, not a paragraph.
    static let messageLimit = 60

    /// Colours a halo can be. Decoration the sender picks, not a category the
    /// app assigns — there is no vocabulary of approved signal types.
    static let palette: [Color] = [.pink, .orange, .mint, .yellow, .cyan, .purple, .green, .blue]

    var name: String = ""
    var message: String = ""
    var tintIndex: Int = 0

    /// A picture, already shrunk. Kept small on purpose: over Bluetooth a halo
    /// has to travel through a brief connection at a few kilobytes a second, so
    /// a full-resolution photo would take the best part of a minute to arrive.
    var imageData: Data?

    /// Trimmed and clipped to length. Applied as you type, so the limit is
    /// visible rather than enforced silently at the last moment.
    var clamped: HaloDraft {
        HaloDraft(name: String(name.prefix(Self.nameLimit)),
                  message: String(message.prefix(Self.messageLimit)),
                  tintIndex: min(max(tintIndex, 0), Self.palette.count - 1),
                  imageData: imageData)
    }

    /// Nothing to say means nothing to broadcast — silence is a valid state,
    /// not an empty balloon.
    var isBroadcastable: Bool {
        imageData != nil
            || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var profile: HaloProfile {
        let clamped = self.clamped
        return HaloProfile(name: clamped.name.trimmingCharacters(in: .whitespacesAndNewlines),
                           message: clamped.message.trimmingCharacters(in: .whitespacesAndNewlines),
                           tint: Self.palette[clamped.tintIndex],
                           imageData: clamped.imageData)
    }
}
