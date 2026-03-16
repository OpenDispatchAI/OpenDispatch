//
//  OpenDispatchUITests.swift
//  OpenDispatchUITests
//
//  Created by Jelle Kapitein on 15/03/2026.
//

import XCTest

final class OpenDispatchUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testListenButtonDoesNotCrashApp() throws {
        let app = XCUIApplication()
        app.launch()

        let listenButton = app.buttons["Listen"]
        XCTAssertTrue(listenButton.waitForExistence(timeout: 5))
        listenButton.tap()

        dismissSystemAlertsIfNeeded()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.tabBars.firstMatch.exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    private func dismissSystemAlertsIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButtons = ["Allow", "OK", "Continue"]

        for title in allowButtons {
            let button = springboard.buttons[title]
            if button.waitForExistence(timeout: 2) {
                button.tap()
            }
        }
    }
}
