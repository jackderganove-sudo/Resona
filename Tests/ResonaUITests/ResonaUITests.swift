//
//  ResonaUITests.swift
//  ResonaUITests
//
//  A full tour through the app in portrait and landscape on the iPad
//  simulator, a screenshot (XCTAttachment, kept) after every step. No
//  YouTube login, no credentials: everything used here works signed out.
//  The app runs with -ResonaUITest (mpv ao=null) in German.
//
//  Steps never hard-fail on a missing element — a missing button is
//  recorded (XCTExpect-style soft failure) and the tour continues, so one
//  broken screen doesn't hide all the others.
//

import XCTest

final class ResonaUITests: XCTestCase {
    private var app: XCUIApplication!
    private var prefix = ""
    private var step = 0

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-ResonaUITest", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
    }

    func test1Portrait() {
        XCUIDevice.shared.orientation = .portrait
        prefix = "portrait"
        tour()
    }

    func test2Landscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        prefix = "landscape"
        tour()
    }

    // MARK: Tour

    private func tour() {
        app.launch()
        sleep(4)
        snap("start")

        tabs()
        searchAndPlay()
        player()
        artistAndAlbum()
        settings()
    }

    private func tabs() {
        for tab in ["home", "search", "library"] {
            if tap("tab.\(tab)") {
                sleep(2)
                snap("tab-\(tab)")
            }
        }
    }

    private func searchAndPlay() {
        guard tap("tab.search") else { return }
        let field = element("search.field")
        guard field.waitForExistence(timeout: 8) else { return softFail("search field missing") }
        field.tap()
        field.typeText("numb")
        // Live suggestions while typing.
        let suggestion = element("suggestion.item")
        if suggestion.waitForExistence(timeout: 10) || element("suggestion.text").waitForExistence(timeout: 3) {
            sleep(1)
            snap("search-suggestions")
        } else {
            softFail("no live suggestions")
        }
        // Submit → results.
        field.typeText("\n")
        sleep(5)
        snap("search-results")
        // Play the first song.
        let song = app.descendants(matching: .any).matching(identifier: "result.song").firstMatch
        if song.waitForExistence(timeout: 10) {
            // Tap the title (the row's own button), not the container centre.
            let title = song.staticTexts.firstMatch
            (title.exists ? title : song).tap()
            _ = element("miniplayer").waitForExistence(timeout: 20)
            sleep(2)
            snap("playing-miniplayer")
        } else {
            softFail("no song result")
        }
    }

    private func player() {
        guard tap("miniplayer", timeout: 15) else { return }
        sleep(3)
        snap("player")
        // The player may come up with the lyrics already open.
        if visibleButton("lyrics.close", attempts: 2) != nil {
            closeOverlay()
            snap("player-lyrics-were-open")
        }

        // Lyrics (in landscape the full-screen lyrics layout), closed by
        // swiping down on the header / top bar — by coordinates: element
        // queries inside the animated lyrics view take very long.
        if tap("player.pill.quote.bubble") {
            sleep(5)
            snap("lyrics")   // shown in the app; not embedded in docs/
            let window = app.windows.firstMatch
            let x: CGFloat = prefix == "landscape" ? 0.72 : 0.3
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.075))
            start.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.75)))
            sleep(2)
            snap("lyrics-after-swipe")
            if !app.buttons["player.pill.list.bullet"].waitForExistence(timeout: 4) {
                softFail("swipe down did not close the lyrics")
                closeOverlay()
            }
        }
        // Queue.
        if tap("player.pill.list.bullet") {
            sleep(2)
            snap("queue")
            closeOverlay()
        }
        // Player menu.
        if tap("player.action.ellipsis") {
            sleep(2)
            snap("player-menu")
            closeOverlay()
        }
        // Sleep timer.
        if tap("player.sleep") {
            sleep(2)
            snap("sleep-timer")
            closeOverlay()
        }
        snap("player-after-sheets")
        if !tap("player.collapse") { app.swipeDown() }
        sleep(2)
    }

    private func artistAndAlbum() {
        guard tap("tab.search") else { return }
        // Results of the earlier search are still there (search path).
        let artist = app.descendants(matching: .any).matching(identifier: "result.artist").firstMatch
        if artist.waitForExistence(timeout: 8) {
            artist.tap()
            sleep(5)
            snap("artist")
            scrollDown()
            snap("artist-scrolled")
            back()
            sleep(2)
            snap("after-artist-back")
        } else {
            softFail("no artist result")
        }
        var album = app.descendants(matching: .any).matching(identifier: "result.album").firstMatch
        if !album.waitForExistence(timeout: 4) {
            scrollDown()
            album = app.descendants(matching: .any).matching(identifier: "result.album").firstMatch
        }
        if album.waitForExistence(timeout: 4) {
            album.tap()
            sleep(5)
            snap("album")
            back()
            sleep(2)
        } else {
            softFail("no album result")
            snap("missing-album")
        }
        let playlist = app.descendants(matching: .any).matching(identifier: "result.playlist").firstMatch
        if playlist.waitForExistence(timeout: 3) {
            playlist.tap()
            sleep(5)
            snap("playlist")
            back()
            sleep(2)
        }
    }

    private func settings() {
        guard tap("tab.home"), tap("account.menu") else { return }
        sleep(1)
        snap("account-menu")
        guard tap("menu.gearshape") else { return }
        sleep(2)
        snap("settings")
        let pages = ["paintpalette", "music.note", "rays", "quote.bubble", "globe",
                     "sparkles", "slider.vertical.3", "internaldrive", "info.circle", "clock.arrow.circlepath"]
        for page in pages {
            let row = element("settings.\(page)")
            if !row.waitForExistence(timeout: 3) || !row.isHittable { scrollDown() }
            guard tap("settings.\(page)") else { continue }
            sleep(2)
            snap("settings-\(page.replacingOccurrences(of: ".", with: "-"))")
            scrollDown()
            snap("settings-\(page.replacingOccurrences(of: ".", with: "-"))-scrolled")
            back()
            sleep(1)
        }
    }

    // MARK: Helpers

    /// First hittable button with this id, polling once per second.
    private func visibleButton(_ identifier: String, attempts: Int) -> XCUIElement? {
        for attempt in 0..<attempts {
            if attempt > 0 { sleep(1) }
            if let button = app.buttons.matching(identifier: identifier).allElementsBoundByIndex
                .first(where: { $0.exists && $0.isHittable }) {
                return button
            }
        }
        return nil
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @discardableResult
    private func tap(_ identifier: String, timeout: TimeInterval = 6) -> Bool {
        var target = element(identifier)
        guard target.waitForExistence(timeout: timeout) else {
            softFail("\(identifier) not found")
            snap("missing-\(identifier)")
            return false
        }
        if !target.isHittable,
           let visible = app.buttons.matching(identifier: identifier).allElementsBoundByIndex
               .first(where: { $0.isHittable }) {
            target = visible
        }
        if !target.isHittable {
            // Covered (sheet) or off screen: tap its centre anyway.
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            target.tap()
        }
        return true
    }

    /// Close button of the overlay (lyrics, queue, player menu), otherwise
    /// Escape (hardware keyboard → app's escape handling), then a swipe down
    /// on the sheet / a tap outside of a popover.
    private func closeOverlay() {
        XCTContext.runActivity(named: "close overlay") { _ in
            for attempt in 1...2 {
                for id in ["lyrics.close", "overlay.close"] {
                    // Several layouts may carry the id; take the visible one.
                    // Buttons only: a query over every element type times out
                    // in the animated lyrics view.
                    let candidates = app.buttons.matching(identifier: id).allElementsBoundByIndex
                    if let button = visibleButton(id, attempts: 3) {
                        let frame = button.frame
                        XCTContext.runActivity(named: "tap \(id) at \(Int(frame.midX)),\(Int(frame.midY)) (attempt \(attempt))") { _ in
                            button.tap()
                        }
                        sleep(2)
                        snap("after-close-\(id)")
                        if visibleButton(id, attempts: 1) == nil { return }
                        // Still there: pull the view down from the button's bar.
                        if id == "lyrics.close", let again = visibleButton(id, attempts: 1) {
                            let start = again.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: -160, dy: 0))
                            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 500)))
                            sleep(2)
                            snap("after-close-swipe")
                            if visibleButton(id, attempts: 1) == nil { return }
                        }
                    } else if !candidates.isEmpty {
                        XCTContext.runActivity(named: "\(id): \(candidates.count) found, none hittable") { _ in }
                    }
                }
                // Landscape lyrics hide their chrome after a while: one tap
                // in the middle wakes it, then try again.
                app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                sleep(1)
            }
            XCTContext.runActivity(named: "fallback: escape / swipe") { _ in
                app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
                sleep(1)
                if element("player.collapse").isHittable { return }
                let window = app.windows.firstMatch
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
                    .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
                sleep(1)
            }
        }
    }

    private func back() {
        let custom = element("nav.back")
        if custom.exists, custom.isHittable { custom.tap(); return }
        let labelled = app.buttons.matching(NSPredicate(format: "label IN {'Back', 'Zurück'}")).firstMatch
        if labelled.exists, labelled.isHittable { labelled.tap(); return }
        let system = app.navigationBars.buttons.firstMatch
        if system.exists, system.isHittable { system.tap(); return }
        // Edge swipe.
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
    }

    private func scrollDown() {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        sleep(1)
    }

    private func snap(_ name: String) {
        step += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        let safe = name.replacingOccurrences(of: ".", with: "-")
        attachment.name = String(format: "%@-%02d-%@", prefix, step, safe)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func softFail(_ message: String) {
        // Recorded as an issue but the tour continues (continueAfterFailure).
        XCTFail("[\(prefix)] \(message)")
    }
}
