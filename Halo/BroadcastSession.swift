//
//  BroadcastSession.swift
//  Halo
//
//  What *you* are broadcasting, and until when.
//

import Foundation

/// Broadcasting is deliberately time-boxed rather than a switch left on.
///
/// Three reasons, in order of importance. It matches what a halo *is* — a
/// signal about right now, not a profile. It means you always know whether you
/// are visible, which "clear user feedback" in the privacy principles demands.
/// And it bounds the battery and radio cost, since a phone advertising from a
/// pocket all day is a different proposition from one doing it for an hour at
/// an event.
struct BroadcastSession {

    /// Offered lengths. Short enough that forgetting to turn it off is never
    /// the same as broadcasting indefinitely.
    enum Length: TimeInterval, CaseIterable, Identifiable {
        case fifteenMinutes = 900
        case oneHour = 3600
        case fourHours = 14400

        var id: TimeInterval { rawValue }

        var label: String {
            switch self {
            case .fifteenMinutes: "15 min"
            case .oneHour: "1 hour"
            case .fourHours: "4 hours"
            }
        }
    }

    let profile: HaloProfile
    let startedAt: Date
    let length: Length

    var endsAt: Date {
        startedAt.addingTimeInterval(length.rawValue)
    }

    func isActive(at moment: Date) -> Bool {
        moment >= startedAt && moment < endsAt
    }

    func remaining(at moment: Date) -> TimeInterval {
        max(endsAt.timeIntervalSince(moment), 0)
    }

    /// Pushing the end further out without restarting, for "I'm staying longer".
    func extended(by length: Length) -> BroadcastSession {
        BroadcastSession(profile: profile,
                         startedAt: startedAt.addingTimeInterval(length.rawValue),
                         length: self.length)
    }
}

/// Owns whatever you are currently broadcasting, if anything.
///
/// Nothing here talks to a radio yet. When it does, this is the single place
/// that decides whether the advertiser should be running — including the case
/// iOS gives us no say in: a force-quit stops advertising outright, so a
/// broadcast can end without anyone choosing to end it.
@MainActor
@Observable
final class BroadcastController {

    private(set) var session: BroadcastSession?

    func start(_ profile: HaloProfile, for length: BroadcastSession.Length, at moment: Date = Date()) {
        session = BroadcastSession(profile: profile, startedAt: moment, length: length)
    }

    func stop() {
        session = nil
    }

    func extend(by length: BroadcastSession.Length) {
        session = session?.extended(by: length)
    }

    /// Deliberately does not clean up after itself: views ask this while
    /// drawing, and changing state during a view update is a bug. Expiry is
    /// handled by `pruneExpired`, called on a timer.
    func isBroadcasting(at moment: Date = Date()) -> Bool {
        session?.isActive(at: moment) ?? false
    }

    /// Drops a session that has run out, so nothing can show a stale
    /// "you are visible".
    func pruneExpired(at moment: Date = Date()) {
        if let session, !session.isActive(at: moment) {
            self.session = nil
        }
    }

    func remaining(at moment: Date = Date()) -> TimeInterval {
        session?.remaining(at: moment) ?? 0
    }
}
