//
//  OmniMusikUITests.swift
//  OmniMusikUITests
//
//  Smoke coverage for the subsystems that were written without a compiler
//  available and had never been run.
//
//  These are not exhaustive tests and are not trying to be. They exist to answer
//  one question per subsystem: does it do anything at all when driven for real?
//  Compiling proved the types line up; a waveform that renders empty, a fan-out
//  that never returns, or a Studio that crashes on present would all have built
//  perfectly clean.
//
//  Deliberately asserting on user-visible text rather than internal state. If the
//  Studio no longer says SIGNAL CHAIN, the interface changed and the test should
//  be revisited, which is the correct outcome.
//

import XCTest

@MainActor
final class OmniMusikUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Helpers

    /// Brings the library to a populated state.
    ///
    /// Sample loading skips titles already present, so this is safe to run on a
    /// simulator whose store survived an earlier test.
    private func populateLibrary() {
        let loadSamples = app.buttons["Load Sample Tracks"]
        if loadSamples.waitForExistence(timeout: 5) {
            loadSamples.tap()
        }
        XCTAssertTrue(
            app.cells.firstMatch.waitForExistence(timeout: 15),
            "Library never showed a track. Sample loading or SwiftData persistence failed."
        )
    }

    // MARK: - Library

    func testSampleTracksPopulateTheLibrary() {
        populateLibrary()
        XCTAssertGreaterThan(app.cells.count, 1, "Expected several sample tracks, got \(app.cells.count).")
    }

    // MARK: - Playback

    func testTappingATrackStartsPlaybackAndDocksTheMiniPlayer() {
        populateLibrary()
        app.cells.firstMatch.tap()

        XCTAssertTrue(
            app.buttons["MiniPlayerPlayPause"].waitForExistence(timeout: 15),
            "Mini player never docked, so the coordinator did not take a current track."
        )
    }

    // MARK: - Studio

    func testStudioOpensAndRendersTheSignalChain() {
        populateLibrary()

        // The Studio is reachable from the row's context menu.
        app.cells.firstMatch.press(forDuration: 1.2)

        let openInStudio = app.buttons["Open in Studio"]
        XCTAssertTrue(openInStudio.waitForExistence(timeout: 5), "Context menu did not offer the Studio.")
        openInStudio.tap()

        // Reaching this point means waveform analysis ran without trapping, which
        // is the part that had never executed.
        XCTAssertTrue(
            app.staticTexts["SIGNAL CHAIN"].waitForExistence(timeout: 20),
            "Studio did not render. Waveform generation is the most likely culprit."
        )

        app.buttons["Cancel"].tap()
    }

    // MARK: - Search

    func testSearchFansOutAndIsolatesTheUnavailableSource() {
        populateLibrary()
        app.buttons["Search"].tap()

        let field = app.searchFields["Songs and artists"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Search field never appeared.")
        field.tap()
        field.typeText("a")

        // Apple Music is a deliberate stub reporting unavailable. Seeing its note
        // proves three things at once: the fan-out ran, the unavailable source was
        // isolated rather than failing the whole search, and the note reached the UI.
        XCTAssertTrue(
            app.staticTexts["Apple Music isn't connected yet."].waitForExistence(timeout: 20),
            "No per-source note appeared. The fan-out did not complete or failure isolation is broken."
        )
    }

    // MARK: - Playlists

    /// End-to-end: library -> context menu -> new playlist -> playlist detail.
    ///
    /// Uses a unique name per run because playlists persist in the simulator's
    /// store between runs, and a fixed name would start matching an earlier
    /// run's row instead of the one this test created.
    func testCreatingAPlaylistFromTheLibraryAndOpeningIt() {
        populateLibrary()

        let name = "Set \(UUID().uuidString.prefix(6))"

        app.cells.firstMatch.press(forDuration: 1.2)
        let addToPlaylist = app.buttons["Add to Playlist"]
        XCTAssertTrue(addToPlaylist.waitForExistence(timeout: 5), "Context menu did not offer Add to Playlist.")
        addToPlaylist.tap()

        let newPlaylist = app.buttons["New Playlist"].firstMatch
        XCTAssertTrue(newPlaylist.waitForExistence(timeout: 5), "Add-to-playlist sheet did not offer a new playlist.")
        newPlaylist.tap()

        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Name prompt never appeared.")
        field.typeText(name)
        app.alerts.buttons["Create"].tap()

        // Creating from here seeds the playlist with the track in one step.
        app.buttons["Playlists"].tap()
        let row = app.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "New playlist did not appear in the index.")

        XCTAssertTrue(
            app.staticTexts["1 track · 0:09"].waitForExistence(timeout: 5)
                || app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "1 track")).firstMatch.exists,
            "Playlist row did not summarise its contents from the stored snapshot."
        )

        row.tap()
        XCTAssertTrue(
            app.buttons["Play"].waitForExistence(timeout: 10),
            "Playlist detail did not resolve its entries into a playable state."
        )
    }

    // MARK: - Queue

    func testQueueViewListsWhatIsPlaying() {
        populateLibrary()
        app.cells.firstMatch.tap()

        XCTAssertTrue(app.buttons["MiniPlayerPlayPause"].waitForExistence(timeout: 15))

        // Expand the mini player into Now Playing, then open the queue from it.
        // Queried by identifier rather than by title, because the same title is
        // also on the library row behind it.
        app.buttons["MiniPlayerExpand"].tap()

        let queueButton = app.buttons["NowPlayingQueue"]
        XCTAssertTrue(queueButton.waitForExistence(timeout: 10), "Now Playing did not offer the queue.")
        queueButton.tap()

        XCTAssertTrue(
            app.staticTexts["Now Playing"].waitForExistence(timeout: 10),
            "Queue view did not render its Now Playing section."
        )
    }

    // MARK: - Account

    func testAccountTabReportsSignInIsNotConfigured() {
        app.buttons["Account"].tap()

        // Cognito has no user pool yet, so the honest state is an explanation
        // rather than a button that cannot work.
        XCTAssertTrue(
            app.staticTexts["Sign-in not configured in this build"].waitForExistence(timeout: 10),
            "Account screen did not report its unconfigured state."
        )
    }
}
