import XCTest

/// Drives the physical-device recording for App Review. Not part of `make test`.
final class ReviewWalkthroughUITests: XCTestCase {
    private let app = XCUIApplication()

    func testWalkthroughForAppReview() {
        continueAfterFailure = true
        app.launch()
        passOnboarding()
        pause(1.4)

        addPastTrip()
        pause(1.4)
        editTrip()
        pause(1.0)
        recordBriefly()
        pause(1.0)
        showExportAndPlus()
        pause(1.5)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func passOnboarding() {
        let cont = app.buttons["Continue"]
        if cont.waitForExistence(timeout: 3) {
            cont.tap()
            pause(0.8)
            if cont.waitForExistence(timeout: 2) {
                cont.tap()
                pause(0.8)
            }
        }
        let start = app.buttons["Start using FairMile"]
        if start.waitForExistence(timeout: 2) {
            start.tap()
        }
        _ = app.buttons["Add a past trip"].waitForExistence(timeout: 8)
    }

    private func addPastTrip() {
        let add = app.buttons["Add a past trip"]
        guard add.waitForExistence(timeout: 5) else { return }
        add.tap()
        pause(1.0)
        replace(named: "Why was this drive business?", with: "Client visit")
        replace(named: "Start place", with: "Office")
        replace(named: "End place", with: "Client")
        replace(named: "Miles", with: "12.4")
        pause(0.6)
        tapSave()
        pause(1.2)
    }

    private func editTrip() {
        let row = app.staticTexts["Client visit"]
        guard row.waitForExistence(timeout: 6) else { return }
        row.tap()
        pause(1.2)
        replace(named: "Miles", with: "12.6")
        pause(0.5)
        tapSave()
        pause(1.0)
    }

    private func recordBriefly() {
        let start = app.buttons["Start trip"]
        guard start.waitForExistence(timeout: 5) else { return }
        start.tap()
        allowLocation()
        pause(2.8)
        let end = app.buttons["End trip"]
        if end.waitForExistence(timeout: 6) {
            end.tap()
            pause(1.6)
        }
        let discard = app.buttons["Discard trip"]
        if discard.waitForExistence(timeout: 3) {
            discard.tap()
            pause(0.7)
            let sheet = app.sheets.buttons["Discard trip"]
            if sheet.waitForExistence(timeout: 2) {
                sheet.tap()
            }
            pause(0.8)
        } else if app.buttons["Close"].waitForExistence(timeout: 2) {
            app.buttons["Close"].tap()
        }
    }

    private func allowLocation() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "使用App时允许", "Allow Once", "允许一次"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }
    }

    private func showExportAndPlus() {
        let export = app.tabBars.buttons["Export"]
        guard export.waitForExistence(timeout: 4) else { return }
        export.tap()
        pause(1.6)
        if app.buttons["See FairMile Plus"].waitForExistence(timeout: 4) {
            app.buttons["See FairMile Plus"].tap()
        } else if app.buttons["Unlimited"].waitForExistence(timeout: 2) {
            app.buttons["Unlimited"].tap()
        }
        pause(1.8)
        let yearly = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'trial' OR label CONTAINS '39.99' OR label CONTAINS[c] 'Yearly'")
        ).firstMatch
        if yearly.waitForExistence(timeout: 8) {
            yearly.tap()
            pause(1.5)
            confirmPurchase()
            pause(2.0)
        }
        if app.buttons["Close"].exists {
            app.buttons["Close"].tap()
            pause(0.6)
        }
        if export.waitForExistence(timeout: 3) {
            export.tap()
            pause(1.4)
        }
        let yearPDF = app.buttons["Export 2026 PDF"]
        if yearPDF.waitForExistence(timeout: 5) {
            yearPDF.tap()
            pause(2.5)
        }
    }

    private func confirmPurchase() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Subscribe", "Purchase", "Buy", "订阅", "购买"] {
            if tapIfPresent(app.buttons[label], timeout: 2) { break }
            if tapIfPresent(springboard.buttons[label], timeout: 1) { break }
        }
        pause(1.2)
        for label in ["OK", "好", "完成", "Done"] {
            if tapIfPresent(springboard.buttons[label], timeout: 2) { return }
            if tapIfPresent(app.buttons[label], timeout: 1) { return }
        }
    }

    @discardableResult
    private func tapIfPresent(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        return true
    }

    private func replace(named name: String, with text: String) {
        let element = field(name)
        guard element.waitForExistence(timeout: 4) else { return }
        if !element.isHittable {
            app.swipeUp()
        }
        element.tap()
        pause(0.3)
        if let current = element.value as? String,
           !current.isEmpty,
           current != element.placeholderValue {
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: min(current.count + 1, 24))
            element.typeText(deletes)
        }
        element.typeText(text)
        pause(0.3)
    }

    private func field(_ name: String) -> XCUIElement {
        let view = app.textViews[name]
        if view.exists { return view }
        return app.textFields[name]
    }

    private func tapSave() {
        let save = app.buttons["Save"]
        guard save.waitForExistence(timeout: 3) else { return }
        if !save.isHittable {
            app.swipeUp()
        }
        save.tap()
    }
}
