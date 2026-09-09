//
//  OmniMusikUITests.swift
//  OmniMusikUITests
//
//  Smoke coverage for the subsystems that were written without a compiler available
//  and had never been run.
//
//  These are not exhaustive and are not trying to be. They exist to answer one
//  question per subsystem: does it do anything at all when driven for real?
//  Compiling proved the types line up; a waveform that renders empty, a fan-out that
//  never returns, or a Studio that crashes on present would all have built cleanly.
//
//  Everything is driven through `tapWhenReady`. Existence and hittability are
//  different things in XCUITest: an element is in the hierarchy while its container
//  is still animating, and a tap in that window lands nowhere and fails silently --
//  the test then fails much later, at whatever it expected the tap to produce.
//  xcodebuild also spreads these across parallel simulator clones, so several
//  iPhones boot and animate at once and that window gets wide. Waiting for
//  hittability puts the failure where the cause is, and removed three separate
//  flaky failures that each passed in isolation.
//
//  Asserting on user-visible text rather than internal state is deliberate. If the
//  Studio no longer says SIGNAL CHAIN, the interface changed and the test should be
//  revisited.
//

import XCTest

@MainActor
final class OmniMusikUITests: XCTestCase {

    private var app: XCUIApplication!

    /// Generous on purpose: `waitForExistence` returns as soon as the element
    /// appears, so a high ceiling costs nothing when things are working.
    private let uiTimeout: TimeInterval = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Helpers

    /// Waits for an element to exist and become hittable, then taps it.
    private func tapWhenReady(_ element: XCUIElement, _ description: String) {
        XCTAssertTrue(element.waitForExistence(timeout: uiTimeout), description)
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
        waitForExpectations(timeout: uiTimeout)
        element.tap()
    }

    private func waitForExistence(_ element: XCUIElement, _ description: String) {
        XCTAssertTrue(element.waitForExistence(timeout: uiTimeout), description)
    }

    /// Taps an item in a context menu, confirming the menu actually closed.
    ///
    /// A context menu will swallow a tap that arrives while it is still settling,
    /// and it does so silently -- the menu simply stays on screen and the test fails
    /// later at whatever the tap was supposed to open. The menu still being present
    /// is the tell, so it is checked and the tap retried once.
    private func tapMenuItem(_ label: String, _ description: String) {
        let item = app.buttons[label]
        XCTAssertTrue(item.waitForExistence(timeout: uiTimeout), description)
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: item)
        waitForExpectations(timeout: uiTimeout)

        item.tap()
        if !item.waitForNonExistence(timeout: 5) {
            item.tap()
            XCTAssertTrue(
                item.waitForNonExistence(timeout: uiTimeout),
                "The context menu would not accept a tap on \(label)."
            )
        }
    }

    /// Brings the library to a populated state.
    ///
    /// Sample loading skips titles already present, so this is safe to run on a
    /// simulator whose store survived an earlier test.
    private func populateLibrary() {
        let loadSamples = app.buttons["Load Sample Tracks"]
        if loadSamples.waitForExistence(timeout: 5) {
            tapWhenReady(loadSamples, "Sample loading button was never tappable.")
        }
        waitForExistence(
            app.cells.firstMatch,
            "Library never showed a track. Sample loading or SwiftData persistence failed."
        )
    }

    private func firstTrackCell() -> XCUIElement {
        let cell = app.cells.firstMatch
        waitForExistence(cell, "No track rows appeared.")
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: cell)
        waitForExpectations(timeout: uiTimeout)
        return cell
    }

    // MARK: - Library

    func testSampleTracksPopulateTheLibrary() {
        populateLibrary()
        XCTAssertGreaterThan(app.cells.count, 1, "Expected several sample tracks, got \(app.cells.count).")
    }

    // MARK: - Playback

    func testTappingATrackStartsPlaybackAndDocksTheMiniPlayer() {
        populateLibrary()
        firstTrackCell().tap()

        waitForExistence(
            app.buttons["MiniPlayerPlayPause"],
            "Mini player never docked, so the coordinator did not take a current track."
        )
    }

    // MARK: - Studio

    func testStudioOpensAndRendersTheSignalChain() {
        populateLibrary()
        firstTrackCell().press(forDuration: 1.2)

        tapMenuItem("Open in Studio", "Context menu did not offer the Studio.")

        // Reaching this point means waveform analysis ran without trapping, which is
        // the part that had never executed.
        waitForExistence(
            app.staticTexts["SIGNAL CHAIN"],
            "Studio did not render. Waveform generation is the most likely culprit."
        )

        tapWhenReady(app.buttons["Cancel"], "Studio had no way out.")
    }

    // MARK: - Search

    func testSearchFansOutAndIsolatesTheUnavailableSource() {
        populateLibrary()
        tapWhenReady(app.buttons["Search"], "Search tab was not tappable.")

        let field = app.searchFields["Songs and artists"]
        tapWhenReady(field, "Search field never appeared.")
        field.typeText("a")

        // Apple Music is a deliberate stub reporting unavailable. Seeing its note
        // proves three things at once: the fan-out ran, the unavailable source was
        // isolated rather than failing the whole search, and the note reached the UI.
        waitForExistence(
            app.staticTexts["Apple Music isn't connected yet."],
            "No per-source note appeared. The fan-out did not complete or failure isolation is broken."
        )
    }

    // MARK: - Playlists

    /// End-to-end: library -> context menu -> new playlist -> playlist detail.
    ///
    /// Uses a unique name per run because playlists persist in the simulator's store
    /// between runs, and a fixed name would start matching an earlier run's row.
    func testCreatingAPlaylistFromTheLibraryAndOpeningIt() {
        populateLibrary()

        let name = "Set \(UUID().uuidString.prefix(6))"

        firstTrackCell().press(forDuration: 1.2)
        tapMenuItem("Add to Playlist", "Context menu did not offer Add to Playlist.")

        tapWhenReady(
            app.buttons["New Playlist"].firstMatch,
            "Add-to-playlist sheet did not offer a new playlist."
        )

        let field = app.alerts.textFields.firstMatch
        waitForExistence(field, "Name prompt never appeared.")
        field.typeText(name)
        tapWhenReady(app.alerts.buttons["Create"], "Name prompt had no Create button.")

        // The sheet must finish dismissing before the tab bar underneath is hittable.
        XCTAssertTrue(
            app.navigationBars["Add to Playlist"].waitForNonExistence(timeout: uiTimeout),
            "The add-to-playlist sheet never dismissed."
        )

        tapWhenReady(app.buttons["Playlists"], "Playlists tab was not tappable.")

        let row = app.staticTexts[name]
        waitForExistence(row, "New playlist did not appear in the index.")

        // Creating from the sheet seeds the playlist with the track in one step, so
        // the row should summarise contents from the stored snapshot.
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "1 track")).firstMatch.exists,
            "Playlist row did not summarise its contents from the stored snapshot."
        )

        tapWhenReady(row, "Playlist row was not tappable.")
        waitForExistence(
            app.buttons["Play"],
            "Playlist detail did not resolve its entries into a playable state."
        )
    }

    // MARK: - Queue

    func testQueueViewListsWhatIsPlaying() {
        populateLibrary()
        firstTrackCell().tap()

        waitForExistence(app.buttons["MiniPlayerPlayPause"], "Playback never started.")

        // Expand the mini player into Now Playing, then open the queue from it.
        // Queried by identifier rather than by title, because the same title is also
        // on the library row behind it.
        tapWhenReady(app.buttons["MiniPlayerExpand"], "Mini player did not expand.")
        tapWhenReady(app.buttons["NowPlayingQueue"], "Now Playing did not offer the queue.")

        waitForExistence(
            app.staticTexts["Now Playing"],
            "Queue view did not render its Now Playing section."
        )
    }

    // MARK: - Account

    func testAccountTabReportsSignInIsNotConfigured() {
        tapWhenReady(app.buttons["Account"], "Account tab was not tappable.")

        // Cognito has no user pool yet, so the honest state is an explanation rather
        // than a button that cannot work.
        waitForExistence(
            app.staticTexts["Sign-in not configured in this build"],
            "Account screen did not report its unconfigured state."
        )
    }
}
