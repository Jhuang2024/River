import XCTest

/// UI tests (§49). The app launches with `-uitest`, which skips onboarding,
/// forces instant speed, disables confirmations and pins the session seed so
/// runs are deterministic.
final class RiverUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
    }

    // MARK: - Helpers

    /// Starts a fresh cash session from the Play tab.
    private func startSession() {
        let quickCash = app.buttons["play.quickCash"]
        XCTAssertTrue(quickCash.waitForExistence(timeout: 8), "Play screen must offer a cash game")
        quickCash.tap()
        let start = app.buttons["setup.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "setup must show a start button")
        start.tap()
        XCTAssertTrue(app.otherElements["hero.holeCards"].waitForExistence(timeout: 8)
                      || app.buttons["table.menu"].waitForExistence(timeout: 8),
                      "the table must appear after starting")
    }

    /// Waits until the hero can act or the hand ended; returns which occurred.
    @discardableResult
    private func waitForDecisionOrHandEnd(timeout: TimeInterval = 15) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.buttons["action.fold"].exists { return "decision" }
            if app.buttons["table.nextHand"].exists { return "handEnd" }
            if app.buttons["table.results"].exists { return "sessionEnd" }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("neither a decision nor a hand end arrived in time")
        return "timeout"
    }

    /// Resolves the current state by folding/checking or dealing the next hand.
    private func advanceOnce() {
        switch waitForDecisionOrHandEnd() {
        case "decision":
            if app.buttons["action.check"].exists {
                app.buttons["action.check"].tap()
            } else {
                app.buttons["action.fold"].tap()
            }
        case "handEnd":
            app.buttons["table.nextHand"].tap()
        default:
            break
        }
    }

    // MARK: - Tests

    func testStartCashGameSeeLegalActionsAndFold() {
        startSession()
        let state = waitForDecisionOrHandEnd()
        if state == "handEnd" {
            app.buttons["table.nextHand"].tap()
            waitForDecisionOrHandEnd()
        }
        // Legal actions are visible: fold plus check or call, never both.
        XCTAssertTrue(app.buttons["action.fold"].exists)
        let check = app.buttons["action.check"].exists
        let call = app.buttons["action.call"].exists
        XCTAssertTrue(check || call, "either check or call must be offered")
        XCTAssertFalse(check && call, "check and call are mutually exclusive")
        app.buttons["action.fold"].tap()
        // Play continues without the fold's actions remaining on screen.
        waitForDecisionOrHandEnd()
    }

    func testBetSizingSheetOpensPresetsAndConfirms() {
        startSession()
        // Find a decision where raising is legal.
        var attempts = 0
        while attempts < 20 {
            let state = waitForDecisionOrHandEnd()
            if state == "decision" && app.buttons["action.betraise"].exists {
                break
            }
            advanceOnce()
            attempts += 1
        }
        guard app.buttons["action.betraise"].exists else {
            XCTFail("no raise opportunity arose within 20 decisions")
            return
        }
        app.buttons["action.betraise"].tap()
        XCTAssertTrue(app.buttons["bet.confirm"].waitForExistence(timeout: 3), "bet sheet must open")
        XCTAssertTrue(app.buttons["bet.preset.min"].exists, "minimum preset must exist")
        XCTAssertTrue(app.buttons["bet.preset.allin"].exists, "all-in preset must exist")
        // Cancel keeps the hand alive.
        app.buttons["bet.cancel"].tap()
        XCTAssertTrue(app.buttons["action.fold"].waitForExistence(timeout: 3), "action bar must return after cancel")
        // Reopen, choose the minimum and confirm.
        app.buttons["action.betraise"].tap()
        XCTAssertTrue(app.buttons["bet.preset.min"].waitForExistence(timeout: 3))
        app.buttons["bet.preset.min"].tap()
        app.buttons["bet.confirm"].tap()
        // The action was accepted: our turn ends.
        waitForDecisionOrHandEnd()
    }

    func testActionHistorySheet() {
        startSession()
        waitForDecisionOrHandEnd()
        app.buttons["table.history"].tap()
        XCTAssertTrue(app.staticTexts["Hand so far"].waitForExistence(timeout: 3), "history sheet must open")
        app.swipeDown(velocity: .fast)
    }

    func testHintSheet() {
        startSession()
        var attempts = 0
        while attempts < 10 {
            if waitForDecisionOrHandEnd() == "decision" { break }
            advanceOnce()
            attempts += 1
        }
        let hint = app.buttons["table.hint"]
        guard hint.exists else {
            XCTFail("hint button must be available in default assistance mode")
            return
        }
        hint.tap()
        // The hint sheet shows an explanation with an equity figure.
        XCTAssertTrue(app.staticTexts["Equity"].waitForExistence(timeout: 8), "hint sheet must present equity")
        app.swipeDown(velocity: .fast)
    }

    func testPauseSaveExitAndContinue() {
        startSession()
        waitForDecisionOrHandEnd()
        app.buttons["table.menu"].tap()
        let exit = app.buttons["menu.exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 3))
        exit.tap()
        // Back on the Play tab with a resumable session.
        XCTAssertTrue(app.buttons["play.continue"].waitForExistence(timeout: 6), "saved session must offer Continue")
        app.buttons["play.continue"].tap()
        XCTAssertTrue(app.buttons["table.menu"].waitForExistence(timeout: 6), "table must resume")
    }

    func testCompleteSeveralHandsRapidTaps() {
        startSession()
        for _ in 0..<8 {
            advanceOnce()
        }
        // Rapid double taps on fold must not crash or double-apply.
        if waitForDecisionOrHandEnd() == "decision" {
            let fold = app.buttons["action.fold"]
            fold.tap()
            if fold.exists {
                fold.tap()
            }
        }
        waitForDecisionOrHandEnd()
    }

    func testBackgroundingDuringPlay() {
        startSession()
        waitForDecisionOrHandEnd()
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()
        XCTAssertTrue(app.buttons["table.menu"].waitForExistence(timeout: 6), "table must survive backgrounding")
    }
}
