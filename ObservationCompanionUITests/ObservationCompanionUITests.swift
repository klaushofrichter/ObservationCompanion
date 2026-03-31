//
//  ObservationCompanionUITests.swift
//  ObservationCompanionUITests
//
//  E2E tests against the live EEN service.
//  Requires TEST_TOKEN, TEST_BASE_URL, TEST_CAMERA_ID environment variables
//  (set by run-e2e-tests.sh).
//

import XCTest

final class ObservationCompanionUITests: XCTestCase {

    private var app: XCUIApplication!
    private var credentials: [String: Any]?

    /// Whether live credentials (including camera ID) are available for injection.
    private var hasCredentials: Bool {
        guard let creds = credentials else { return false }
        return creds["accessToken"] != nil && creds["cameraId"] != nil && creds["httpsBaseUrl"] != nil
    }

    /// Load credentials from test-credentials.json (written by run-e2e-tests.sh)
    /// or from environment variables if available.
    private static func loadCredentials() -> [String: Any]? {
        // Try environment variables first
        let env = ProcessInfo.processInfo.environment
        if let token = env["TEST_TOKEN"],
           let baseUrl = env["TEST_BASE_URL"],
           let cameraId = env["TEST_CAMERA_ID"] {
            return [
                "accessToken": token,
                "httpsBaseUrl": baseUrl,
                "cameraId": cameraId,
                "expiresIn": env["TEST_TTL"] ?? "3600"
            ]
        }

        // Try credentials file at known locations
        // Prefer e2e-credentials.json (has cameraId) over test-credentials.json
        let projectDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ObservationCompanionUITests/
            .deletingLastPathComponent() // ObservationCompanion/
        let toolkitDir = projectDir
            .deletingLastPathComponent() // examples/
            .deletingLastPathComponent() // EENSwiftToolkit/

        let candidatePaths = [
            projectDir.appendingPathComponent("e2e-credentials.json"),
            toolkitDir.appendingPathComponent("test-credentials.json")
        ]

        for path in candidatePaths {
            if let data = try? Data(contentsOf: path),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["accessToken"] != nil,
               json["cameraId"] != nil {
                return json
            }
        }

        // Fallback: test-credentials.json without cameraId (will skip credential tests)
        for path in candidatePaths {
            if let data = try? Data(contentsOf: path),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["accessToken"] != nil {
                return json
            }
        }
        return nil
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        credentials = Self.loadCredentials()
        app = XCUIApplication()

        // Inject credentials as the env vars the app expects
        if let creds = credentials {
            if let token = creds["accessToken"] as? String {
                app.launchEnvironment["EEN_TOKEN"] = token
            }
            if let baseUrl = creds["httpsBaseUrl"] as? String {
                app.launchEnvironment["EEN_BASE_URL"] = baseUrl
            }
            if let cameraId = creds["cameraId"] as? String {
                app.launchEnvironment["EEN_CAMERA_ID"] = cameraId
            }
            if let ttl = creds["expiresIn"] as? String {
                app.launchEnvironment["EEN_TTL"] = ttl
            } else if let ttl = creds["expiresIn"] as? Int {
                app.launchEnvironment["EEN_TTL"] = String(ttl)
            }
        }
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tests

    /// Without credentials the app should show the scanner/login screen.
    @MainActor
    func testAppLaunchShowsScanner() throws {
        let cleanApp = XCUIApplication()
        // Launch without any credentials
        cleanApp.launch()

        let scanner = cleanApp.otherElements["ScannerView"]
        if !scanner.waitForExistence(timeout: 10) {
            // Debug: check what's actually on screen
            XCTFail("ScannerView not found. Debug: \(cleanApp.debugDescription.prefix(3000))")
            return
        }

        let loginButton = cleanApp.buttons["OAuthLoginButton"]
        XCTAssertTrue(loginButton.exists, "OAuth login button should be visible")
    }

    /// Inject token → app should transition through connecting to live view.
    @MainActor
    func testTokenInjectionConnectsToCamera() throws {
        try XCTSkipUnless(hasCredentials, "Skipping: no TEST_TOKEN set")

        app.launch()

        // Should pass through connecting state
        let connectingView = app.otherElements["ConnectingView"]
        // It may appear briefly or be skipped if connection is fast
        _ = connectingView.waitForExistence(timeout: 5)

        // Should reach live view within 30s
        let liveView = app.otherElements["LiveView"]
        if !liveView.waitForExistence(timeout: 30) {
            // Debug: dump what's visible
            let errorView = app.otherElements["ErrorView"]
            let scannerView = app.otherElements["ScannerView"]
            let connecting = connectingView.exists
            XCTFail("LiveView did not appear. ErrorView=\(errorView.exists), ScannerView=\(scannerView.exists), ConnectingView=\(connecting). Debug: \(app.debugDescription.prefix(2000))")
        }
    }

    /// Camera name button should display non-empty text once live.
    @MainActor
    func testCameraNameDisplayed() throws {
        try XCTSkipUnless(hasCredentials, "Skipping: no TEST_TOKEN set")

        app.launch()

        let liveView = app.otherElements["LiveView"]
        guard liveView.waitForExistence(timeout: 30) else {
            XCTFail("LiveView did not appear")
            return
        }

        let cameraButton = app.buttons["CameraNameButton"]
        XCTAssertTrue(cameraButton.waitForExistence(timeout: 5), "Camera name button should exist")
        // The button label should contain some text (camera name or ID)
        let label = cameraButton.label
        XCTAssertFalse(label.isEmpty, "Camera name button should have a non-empty label")
    }

    /// The "LIVE HD" badge should appear once video starts playing.
    @MainActor
    func testLiveBadgeAppears() throws {
        try XCTSkipUnless(hasCredentials, "Skipping: no TEST_TOKEN set")

        app.launch()

        let liveView = app.otherElements["LiveView"]
        guard liveView.waitForExistence(timeout: 30) else {
            XCTFail("LiveView did not appear")
            return
        }

        // The live badge may take time to appear (video must start playing first)
        // Search across all element types since SwiftUI rendering varies
        let liveBadgeAny = app.descendants(matching: .any)["LiveBadge"]
        let liveText = app.staticTexts["LIVE HD"]
        let found = liveBadgeAny.waitForExistence(timeout: 30) || liveText.waitForExistence(timeout: 5)
        XCTAssertTrue(found, "LIVE HD badge should appear when video is playing")
    }

    /// Event feed header and count should be visible in live view.
    @MainActor
    func testEventFeedAppears() throws {
        try XCTSkipUnless(hasCredentials, "Skipping: no TEST_TOKEN set")

        app.launch()

        let liveView = app.otherElements["LiveView"]
        guard liveView.waitForExistence(timeout: 30) else {
            XCTFail("LiveView did not appear")
            return
        }

        let header = app.otherElements["EventFeedHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 10), "Event feed header should be visible")

        let eventCount = app.staticTexts["EventCount"]
        XCTAssertTrue(eventCount.waitForExistence(timeout: 10), "Event count should be visible")
    }

    /// Tapping the close button should return to the scanner view.
    @MainActor
    func testCloseButtonReturnsToScanner() throws {
        try XCTSkipUnless(hasCredentials, "Skipping: no TEST_TOKEN set")

        app.launch()

        let liveView = app.otherElements["LiveView"]
        guard liveView.waitForExistence(timeout: 30) else {
            XCTFail("LiveView did not appear")
            return
        }

        let closeButton = app.buttons["CloseButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "Close button should exist")
        closeButton.tap()

        let scanner = app.otherElements["ScannerView"]
        XCTAssertTrue(scanner.waitForExistence(timeout: 10), "ScannerView should reappear after tapping close")
    }
}
