//
//  QueueAdvanceTests.swift
//  OmniMusikTests
//
//  Where the queue goes when a track cannot start.
//
//  Reproducing this by hand means a locked phone, a mixed queue, and a Spotify app
//  the OS has already suspended -- conditions that take minutes to arrange and cannot
//  be observed while they hold, because looking at the screen is what changes the
//  answer. The rule is pure precisely so none of that is needed to test it.
//
//  The case worth caring about is the last one: a queue with nothing playable left
//  must stop, not keep looking.
//

import Foundation
import Testing
@testable import OmniMusik

@Suite("Queue advance")
struct QueueAdvanceTests {

    /// Behind a lock screen: local plays, Spotify cannot be woken.
    private let locked: (TrackSource) -> Bool = { $0 != .spotify }
    private let onScreen: (TrackSource) -> Bool = { _ in true }

    @Test("Takes the very next track when it can play")
    func takesTheNextTrack() {
        let index = QueueAdvance.nextPlayableIndex(
            after: 0, in: [.local, .local, .spotify], canStart: locked
        )
        #expect(index == 1)
    }

    @Test("Passes over a track whose app cannot be woken")
    func passesOverUnplayable() {
        let index = QueueAdvance.nextPlayableIndex(
            after: 0, in: [.local, .spotify, .local], canStart: locked
        )
        #expect(index == 2)
    }

    @Test("Passes over a run of them rather than only one")
    func passesOverARun() {
        let index = QueueAdvance.nextPlayableIndex(
            after: 0, in: [.local, .spotify, .spotify, .spotify, .local], canStart: locked
        )
        #expect(index == 4)
    }

    /// The one that has to hold. Without it the coordinator would either recurse
    /// until the stack gave out or restart the queue from the top -- and restarting
    /// is worse, because it happens while nobody is looking at the phone.
    @Test("Stops rather than looking forever when nothing is left")
    func stopsWhenNothingIsPlayable() {
        let index = QueueAdvance.nextPlayableIndex(
            after: 0, in: [.local, .spotify, .spotify], canStart: locked
        )
        #expect(index == nil)
    }

    @Test("Never looks backwards, even past tracks that could play")
    func neverLooksBackwards() {
        let index = QueueAdvance.nextPlayableIndex(
            after: 2, in: [.local, .local, .local], canStart: onScreen
        )
        #expect(index == nil)
    }

    @Test("Reaching the end of the queue is not an error")
    func endOfQueue() {
        #expect(QueueAdvance.nextPlayableIndex(after: 0, in: [], canStart: onScreen) == nil)
        #expect(QueueAdvance.nextPlayableIndex(after: 0, in: [.local], canStart: onScreen) == nil)
    }

    /// The same queue, the same position, a different answer -- because playability
    /// is a property of the moment rather than of the track. This is the reason
    /// `canStart` is a parameter instead of something the queue works out itself.
    @Test("The same Spotify track is playable with the app on screen")
    func foregroundChangesTheAnswer() {
        let sources: [TrackSource] = [.local, .spotify, .local]
        #expect(QueueAdvance.nextPlayableIndex(after: 0, in: sources, canStart: locked) == 2)
        #expect(QueueAdvance.nextPlayableIndex(after: 0, in: sources, canStart: onScreen) == 1)
    }

    @Test("Apple Music is never skipped: a system process needs no waking")
    func appleMusicIsNotSkipped() {
        let index = QueueAdvance.nextPlayableIndex(
            after: 0, in: [.local, .appleMusic], canStart: locked
        )
        #expect(index == 1)
    }
}
