import XCTest

/// Drives Firelight and writes the App Store screenshots.
///
/// Not a test of anything — it asserts almost nothing, and a failure here
/// means the store listing needs regenerating, not that the app is broken.
/// It lives in its own scheme so `scripts/build.sh test` stays fast and
/// stays about correctness.
///
/// Everything it photographs is the **demo library**: public-domain text,
/// a synthesised voice, covers drawn by `make_demo_library.py`. That is
/// deliberate. Screenshotting a real Audiobookshelf library would put
/// publishers' cover art in App Store marketing material, which is a
/// copyright problem the app itself does not have.
///
/// The destination folder arrives as `TEST_RUNNER_SCREENSHOT_DIR`. The
/// prefix is not decoration: `xcodebuild` treats a bare `NAME=value` as a
/// *build setting*, and only forwards variables prefixed `TEST_RUNNER_` into
/// the test process's environment, stripping the prefix on the way.
///
///     xcodebuild test -scheme FirelightScreenshots \
///       -destination 'name=iPhone 17 Pro Max' \
///       TEST_RUNNER_SCREENSHOT_DIR=/path/to/docs/screenshots
final class AppStoreScreenshots: XCTestCase {
    private var app: XCUIApplication!
    private var directory: URL!
    private var taken = 0

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Where to write, without environment plumbing. `xcodebuild` does not
        // forward `TEST_RUNNER_*` into the test process here — verified by
        // dumping the environment and finding nothing — and a bare `NAME=`
        // on the command line is a build setting, not an environment
        // variable. `#filePath` is this file's path on the machine that
        // compiled it, so the screenshots land beside the source that made
        // them with nothing to pass in.
        let environment = ProcessInfo.processInfo.environment
        let override = environment["SCREENSHOT_DIR"] ?? environment["TEST_RUNNER_SCREENSHOT_DIR"]
        let beside = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Screenshots/
            .deletingLastPathComponent()   // the repository
            .appending(path: "docs/screenshots")
        directory = override.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? beside
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        app = XCUIApplication()
        // The run has to load a book to photograph the player, and the
        // simulator plays through the host's speakers. There is no simctl
        // mute, so the app is asked to make no sound at all.
        app.launchArguments = ["-FirelightSilent"]
        app.launch()
    }

    override func tearDownWithError() throws {
        // This run drives the app into playback to photograph the player, and
        // a simulator left playing keeps playing through the host's speakers
        // long after the test has finished. Stop it, always, including when
        // the test threw part-way.
        silence()
        app?.terminate()
        app = nil
    }

    func testCaptureStoreScreenshots() throws {
        try openDemoLibrary()

        capture("home")

        // The grid, which is where most of the artwork is.
        if app.buttons["Library"].waitForExistence(timeout: 5) {
            app.buttons["Library"].tap()
            capture("library")
            app.buttons["Listening"].tap()
        }

        try openFirstBook()
        capture("book")

        try startPlaying()
        capture("player")

        try openChapters()
        capture("chapters")

        // App Store Connect asks for a review screenshot per in-app purchase.
        // One shot of the tip jar serves all four, and showing them in the
        // app is what the reviewer is actually checking.
        try openTipJar()
        capture("tip-jar")

        XCTAssertGreaterThanOrEqual(taken, 3, "Too few screens were reached to make a listing.")
    }

    // MARK: - Navigation

    /// The opening screen offers a sample library; everything else follows
    /// from it.
    private func openDemoLibrary() throws {
        let demo = app.buttons["Look around first"]
        if demo.waitForExistence(timeout: 10) {
            demo.tap()
        }
        // Either it just signed in, or a library was already there.
        XCTAssertTrue(
            app.staticTexts["Listening"].waitForExistence(timeout: 20),
            "The library never appeared."
        )
        // Let the covers arrive before photographing a shelf of placeholders.
        Thread.sleep(forTimeInterval: 3)
    }

    private func openFirstBook() throws {
        let book = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Alice")
        ).firstMatch
        guard book.waitForExistence(timeout: 10) else {
            throw XCTSkip("No demo book on screen to open.")
        }
        book.tap()
        Thread.sleep(forTimeInterval: 2)
    }

    /// Starts playback, then stops it immediately.
    ///
    /// The player screen needs a loaded book to photograph, not a *sounding*
    /// one. Leaving it playing meant a screenshot run filled the room with
    /// narration for the best part of a minute — and killing the run part-way
    /// skipped the teardown that would have stopped it. Pausing within the
    /// first second makes that impossible rather than merely tidy.
    private func startPlaying() throws {
        let play = app.buttons["Play"]
        guard play.waitForExistence(timeout: 10) else {
            throw XCTSkip("No Play button on the detail screen.")
        }
        play.tap()
        silence()
        Thread.sleep(forTimeInterval: 2)

        // The mini player expands into the full one.
        let mini = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Alice")
        ).firstMatch
        if mini.exists { mini.tap() }
        Thread.sleep(forTimeInterval: 2)
    }

    private func openChapters() throws {
        let chapters = app.buttons["Chapters"]
        guard chapters.waitForExistence(timeout: 5) else {
            throw XCTSkip("No Chapters button in the player.")
        }
        chapters.tap()
        Thread.sleep(forTimeInterval: 2)
    }

    /// Settings → the tip jar.
    ///
    /// Needs the StoreKit configuration wired into the scheme, or the
    /// products never load and the screen shows its empty state instead of
    /// four tips.
    private func openTipJar() throws {
        // Unwind properly, innermost first. The Chapters *sheet* sits over
        // the player, the player is a full-screen cover over the book's
        // detail screen, and Settings lives on the home screen's toolbar.
        // Leaving the sheet up meant every later tap landed on it instead:
        // the accessibility tree showed the player's controls and the home
        // screen at once, and the Settings tap hit nothing.
        if app.buttons["Done"].exists {
            app.buttons["Done"].tap()
            Thread.sleep(forTimeInterval: 1)
        }
        if app.buttons["Close the player"].exists {
            app.buttons["Close the player"].tap()
            Thread.sleep(forTimeInterval: 1)
        }
        for _ in 0..<3 where !app.buttons["Settings"].exists {
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists else { break }
            back.tap()
            Thread.sleep(forTimeInterval: 1)
        }

        let settings = app.buttons["Settings"].firstMatch
        guard settings.waitForExistence(timeout: 5) else {
            throw XCTSkip("Never got back to a screen with Settings on it.")
        }
        settings.tap()
        Thread.sleep(forTimeInterval: 2)

        // A SwiftUI List renders lazily, so a row far down does not exist in
        // the accessibility tree until it has been scrolled near. Waiting for
        // it never succeeds; scrolling to it does. The row is a navigation
        // link, which surfaces as a button on some iOS versions and a cell on
        // others, so try both rather than guess.
        var scrolls = 0
        while tipJarRow == nil, scrolls < 10 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
            scrolls += 1
        }
        guard let row = tipJarRow else {
            throw XCTSkip("Never reached the Support Firelight row.")
        }
        row.tap()
        Thread.sleep(forTimeInterval: 5)

        // XcodeGen writes the StoreKit configuration into the scheme's *Run*
        // action only, and `xcodebuild test` does not inherit it, so the
        // products do not load here and the screen shows "The App Store isn't
        // reachable right now." A screenshot of that is worse than none.
        //
        // Take this one by hand instead: run the app from Xcode (⌘R, which
        // does use the Run action) and photograph Settings → Support
        // Firelight. See docs/App-Store-tip-products.md.
        guard !app.staticTexts["The App Store isn't reachable right now."].exists else {
            throw XCTSkip("Tip products do not load under `xcodebuild test`; take this shot from a ⌘R run.")
        }
    }

    /// The Support Firelight row, however this iOS version chooses to expose it.
    private var tipJarRow: XCUIElement? {
        for candidates in [app.buttons, app.cells, app.staticTexts] {
            let match = candidates["Support Firelight"].firstMatch
            if match.exists { return match }
        }
        return nil
    }

    /// Pauses whatever is playing. Called the moment playback starts, and
    /// again from `tearDown`, because this runs on someone's actual speakers.
    private func silence() {
        for _ in 0..<3 {
            let pause = app.buttons["Pause"].firstMatch
            guard pause.exists else { break }
            pause.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    // MARK: - Capture

    /// Writes a full-resolution PNG, and keeps it in the result bundle too so
    /// a failed run still shows what it saw.
    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        taken += 1
        let file = directory.appending(path: String(format: "%02d-%@.png", taken, name))
        do {
            try screenshot.pngRepresentation.write(to: file)
            print("screenshot: \(file.path)")
        } catch {
            XCTFail("Could not write \(file.path): \(error)")
        }
    }
}
