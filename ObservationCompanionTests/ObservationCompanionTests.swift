//
//  ObservationCompanionTests.swift
//  ObservationCompanionTests
//

import Testing
import Foundation
@testable import ObservationCompanion
@testable import EENApiToolkit

// MARK: - Test Helpers

@MainActor
private func makeAppState() -> AppState {
    let toolkit = EENToolkit(config: EENToolkitConfig(
        proxyUrl: "http://localhost:9999",
        clientId: "test-client",
        redirectUri: "http://localhost:9999"
    ))
    return AppState(toolkit: toolkit)
}

private func makeURL(_ path: String = "viewer", query: [String: String] = [:]) -> URL {
    var components = URLComponents()
    components.scheme = AppConfig.urlScheme
    components.host = path
    components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
    return components.url!
}

// MARK: - Countdown Helpers (extracted from TokenCountdownView logic)

private func timeString(for seconds: Int) -> String {
    let days = seconds / 86400
    let hours = (seconds % 86400) / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60

    if days > 0 {
        return "\(days)d \(hours)h"
    } else if hours > 0 {
        return String(format: "%dh %02dm", hours, minutes)
    } else {
        return String(format: "%d:%02d", minutes, secs)
    }
}

private func progress(remaining: Int, total: TimeInterval) -> Double {
    guard total > 0 else { return 0 }
    return max(0, min(1, Double(remaining) / total))
}

private func barColorName(remaining: Int) -> String {
    if remaining < 300 { return "red" }
    if remaining < 900 { return "orange" }
    return "green"
}

// MARK: - EventTypeHash Tests

@Suite("EventTypeHash")
struct EventTypeHashTests {

    @Test("hash is deterministic")
    func hashDeterministic() {
        let h1 = EventTypeHash.hash("een.motionDetectionEvent.v1")
        let h2 = EventTypeHash.hash("een.motionDetectionEvent.v1")
        #expect(h1 == h2)
    }

    @Test("hash produces 3-character string")
    func hashLength() {
        let h = EventTypeHash.hash("een.motionDetectionEvent.v1")
        #expect(h.count == 3)
    }

    @Test("different inputs produce different hashes")
    func hashDistinct() {
        let h1 = EventTypeHash.hash("een.motionDetectionEvent.v1")
        let h2 = EventTypeHash.hash("een.cameraOnlineEvent.v1")
        #expect(h1 != h2)
    }

    @Test("hash uses alphanumeric characters only")
    func hashCharacterSet() {
        let h = EventTypeHash.hash("een.tamperDetectionEvent.v1")
        let validChars = CharacterSet.alphanumerics
        for scalar in h.unicodeScalars {
            #expect(validChars.contains(scalar), "Unexpected character: \(scalar)")
        }
    }

    @Test("empty string produces a hash")
    func hashEmptyInput() {
        let h = EventTypeHash.hash("")
        #expect(h.count == 3)
    }

    // buildLookup

    @Test("buildLookup maps hash to event type")
    func buildLookupBasic() {
        let types = ["een.motionDetectionEvent.v1", "een.cameraOnlineEvent.v1"]
        let lookup = EventTypeHash.buildLookup(types)
        #expect(lookup.count == 2)
        for type in types {
            let h = EventTypeHash.hash(type)
            #expect(lookup[h] == type)
        }
    }

    @Test("buildLookup with empty list")
    func buildLookupEmpty() {
        let lookup = EventTypeHash.buildLookup([])
        #expect(lookup.isEmpty)
    }

    // resolve

    @Test("resolve maps comma-separated hashes back to types")
    func resolveBasic() {
        let types = ["een.motionDetectionEvent.v1", "een.cameraOnlineEvent.v1"]
        let lookup = EventTypeHash.buildLookup(types)
        let hashes = types.map { EventTypeHash.hash($0) }.joined(separator: ",")
        let resolved = EventTypeHash.resolve(hashString: hashes, lookup: lookup)
        #expect(Set(resolved) == Set(types))
    }

    @Test("resolve skips unknown hashes")
    func resolveUnknown() {
        let lookup = EventTypeHash.buildLookup(["een.motionDetectionEvent.v1"])
        let resolved = EventTypeHash.resolve(hashString: "zzz,yyy", lookup: lookup)
        #expect(resolved.isEmpty)
    }

    @Test("resolve handles empty input")
    func resolveEmpty() {
        let resolved = EventTypeHash.resolve(hashString: "", lookup: [:])
        #expect(resolved.isEmpty)
    }

    @Test("resolve handles whitespace around hashes")
    func resolveWhitespace() {
        let types = ["een.motionDetectionEvent.v1"]
        let lookup = EventTypeHash.buildLookup(types)
        let h = EventTypeHash.hash(types[0])
        let resolved = EventTypeHash.resolve(hashString: " \(h) , \(h) ", lookup: lookup)
        #expect(resolved.count == 2)
    }

    // displayName

    @Test("displayName strips een. prefix and .v1 suffix")
    func displayNameStripsPrefix() {
        let name = EventTypeHash.displayName("een.motionDetectionEvent.v1")
        #expect(name == "Motion Detection")
    }

    @Test("displayName strips Event suffix")
    func displayNameStripsEvent() {
        let name = EventTypeHash.displayName("een.cameraOnlineEvent.v1")
        #expect(name == "Camera Online")
    }

    @Test("displayName splits camelCase")
    func displayNameCamelCase() {
        let name = EventTypeHash.displayName("tamperDetection")
        #expect(name == "Tamper Detection")
    }

    @Test("displayName capitalizes first letter of each word")
    func displayNameCapitalize() {
        let name = EventTypeHash.displayName("simple")
        #expect(name == "Simple")
    }

    // eventDescription

    @Test("eventDescription combines name and time")
    func eventDescriptionBasic() {
        let desc = EventTypeHash.eventDescription(type: "een.motionDetectionEvent.v1", startTimestamp: "2024-01-15T10:30:45.123Z")
        #expect(desc == "Motion Detection @ 10:30:45.123")
    }

    @Test("eventDescription with empty timestamp")
    func eventDescriptionNoTimestamp() {
        let desc = EventTypeHash.eventDescription(type: "een.motionDetectionEvent.v1", startTimestamp: "")
        #expect(desc == "Motion Detection")
    }
}

// MARK: - CameraEvent Tests

@Suite("CameraEvent")
struct CameraEventTests {

    @Test("typeEmoji returns eye for motion detection")
    func emojiMotion() {
        let event = CameraEvent(type: "een.motionDetectionEvent.v1", actorId: "cam1", description: "test")
        #expect(event.typeEmoji == "👁️")
    }

    @Test("typeEmoji returns person for person detection")
    func emojiPerson() {
        let event = CameraEvent(type: "een.personDetectionEvent.v1", actorId: "cam1", description: "test")
        #expect(event.typeEmoji == "🧑")
    }

    @Test("typeEmoji returns car for vehicle detection")
    func emojiVehicle() {
        let event = CameraEvent(type: "een.vehicleDetectionEvent.v1", actorId: "cam1", description: "test")
        #expect(event.typeEmoji == "🚗")
    }

    @Test("typeEmoji returns warning for tamper detection")
    func emojiTamper() {
        let event = CameraEvent(type: "een.tamperDetectionEvent.v1", actorId: "cam1", description: "test")
        #expect(event.typeEmoji == "⚠️")
    }

    @Test("typeEmoji returns robot for EEVA query")
    func emojiEeva() {
        let event = CameraEvent(type: "een.eevaQueryEvent.v1", actorId: "cam1", description: "test")
        #expect(event.typeEmoji == "🤖")
    }

    @Test("typeEmoji returns clipboard for unknown type")
    func emojiUnknown() {
        let event = CameraEvent(type: "something.else", actorId: "cam1", description: "test")
        #expect(event.typeEmoji == "📋")
    }

    @Test("typeEmoji returns clipboard for non-EEN event type")
    func emojiNonEenType() {
        let event = CameraEvent(type: "MOTION_DETECTED", actorId: "cam1", description: "test")
        #expect(event.typeEmoji == "📋")
    }

    @Test("default timestamp is close to now")
    func defaultTimestamp() {
        let before = Date()
        let event = CameraEvent(type: "test", actorId: "cam1", description: "test")
        let after = Date()
        #expect(event.timestamp >= before)
        #expect(event.timestamp <= after)
    }

    @Test("default eventId is nil")
    func defaultEventId() {
        let event = CameraEvent(type: "test", actorId: "cam1", description: "test")
        #expect(event.eventId == nil)
    }

    @Test("confidenceText shows single value as percentage")
    func confidenceSingle() {
        let event = CameraEvent(type: "test", actorId: "cam1", description: "test", confidences: [0.926])
        #expect(event.confidenceText == "92.6% confidence")
    }

    @Test("confidenceText shows range for multiple values")
    func confidenceRange() {
        let event = CameraEvent(type: "test", actorId: "cam1", description: "test", confidences: [0.926, 0.784, 0.902])
        #expect(event.confidenceText == "78.4% to 92.6% confidence")
    }

    @Test("confidenceText is nil when no confidences")
    func confidenceEmpty() {
        let event = CameraEvent(type: "test", actorId: "cam1", description: "test")
        #expect(event.confidenceText == nil)
    }

    @Test("eevaReason is stored and accessible")
    func eevaReason() {
        let event = CameraEvent(type: "een.eevaQueryEvent.v1", actorId: "cam1", description: "test", eevaReason: "a person wearing black pants")
        #expect(event.eevaReason == "a person wearing black pants")
    }

    @Test("eevaReason defaults to nil")
    func eevaReasonDefault() {
        let event = CameraEvent(type: "test", actorId: "cam1", description: "test")
        #expect(event.eevaReason == nil)
    }
}

// MARK: - AppState URL Parsing Tests

@Suite("AppState URL Parsing")
struct AppStateURLParsingTests {

    @Test("valid URL with all params sets connecting state")
    @MainActor func validURL() {
        let state = makeAppState()
        let ttl = String(Int(Date().timeIntervalSince1970) + 3600)
        let url = makeURL(query: [
            "token": "test-token-123",
            "cam": "camera-abc",
            "base": "api.example.com",
            "events": "abc,def",
            "ttl": ttl
        ])
        state.handleViewerURL(url)
        #expect(state.connectionState == .connecting)
        #expect(state.cameraId == "camera-abc")
    }

    @Test("missing token sets error state")
    @MainActor func missingToken() {
        let state = makeAppState()
        let url = makeURL(query: ["cam": "camera-abc", "base": "api.example.com"])
        state.handleViewerURL(url)
        if case .error(let msg) = state.connectionState {
            #expect(msg.contains("Missing parameters"))
        } else {
            #expect(Bool(false), "Expected error state")
        }
    }

    @Test("missing cam sets error state")
    @MainActor func missingCam() {
        let state = makeAppState()
        let url = makeURL(query: ["token": "tok", "base": "api.example.com"])
        state.handleViewerURL(url)
        if case .error = state.connectionState {
            // expected
        } else {
            #expect(Bool(false), "Expected error state")
        }
    }

    @Test("missing base sets error state")
    @MainActor func missingBase() {
        let state = makeAppState()
        let url = makeURL(query: ["token": "tok", "cam": "cam1"])
        state.handleViewerURL(url)
        if case .error = state.connectionState {
            // expected
        } else {
            #expect(Bool(false), "Expected error state")
        }
    }

    @Test("wrong scheme sets error state")
    @MainActor func wrongScheme() {
        let state = makeAppState()
        var components = URLComponents()
        components.scheme = "wrongscheme"
        components.host = "viewer"
        components.queryItems = [
            URLQueryItem(name: "token", value: "tok"),
            URLQueryItem(name: "cam", value: "cam1"),
            URLQueryItem(name: "base", value: "api.example.com")
        ]
        state.handleViewerURL(components.url!)
        if case .error(let msg) = state.connectionState {
            #expect(msg.contains("Invalid URL scheme"))
        } else {
            #expect(Bool(false), "Expected error state")
        }
    }

    @Test("OAuth callback URL is ignored")
    @MainActor func oauthCallback() {
        let state = makeAppState()
        let url = makeURL("callback", query: ["code": "abc", "state": "xyz"])
        state.handleViewerURL(url)
        #expect(state.connectionState == .scanning)
    }

    @Test("URL with no query items sets error")
    @MainActor func noQueryItems() {
        let state = makeAppState()
        var components = URLComponents()
        components.scheme = AppConfig.urlScheme
        components.host = "viewer"
        state.handleViewerURL(components.url!)
        if case .error(let msg) = state.connectionState {
            #expect(msg.contains("Could not parse"))
        } else {
            #expect(Bool(false), "Expected error state")
        }
    }

    @Test("TTL calculates remaining time from epoch")
    @MainActor func ttlCalculation() {
        let state = makeAppState()
        let futureEpoch = String(Int(Date().timeIntervalSince1970) + 1800)
        let url = makeURL(query: [
            "token": "tok",
            "cam": "cam1",
            "base": "api.example.com",
            "ttl": futureEpoch
        ])
        state.handleViewerURL(url)
        // TTL should be approximately 1800 seconds (allow some slack for test execution time)
        #expect(state.tokenTTL > 1790)
        #expect(state.tokenTTL <= 1800)
    }

    @Test("expired TTL uses default")
    @MainActor func expiredTTL() {
        let state = makeAppState()
        let pastEpoch = String(Int(Date().timeIntervalSince1970) - 100)
        let url = makeURL(query: [
            "token": "tok",
            "cam": "cam1",
            "base": "api.example.com",
            "ttl": pastEpoch
        ])
        state.handleViewerURL(url)
        // Expired TTL → nil → defaults to 3600
        #expect(state.tokenTTL == AppState.defaultTokenTTL)
    }

    @Test("valid URL clears previous events")
    @MainActor func clearsEvents() {
        let state = makeAppState()
        let url = makeURL(query: [
            "token": "tok",
            "cam": "cam1",
            "base": "api.example.com"
        ])
        state.handleViewerURL(url)
        #expect(state.events.isEmpty)
    }
}

// MARK: - AppState Reset & Cleanup Tests

@Suite("AppState Reset")
struct AppStateResetTests {

    @Test("reset clears state back to scanning")
    @MainActor func resetToScanning() {
        let state = makeAppState()
        // Set up some state first
        let url = makeURL(query: [
            "token": "tok",
            "cam": "cam1",
            "base": "api.example.com"
        ])
        state.handleViewerURL(url)
        #expect(state.connectionState == .connecting)

        state.reset()
        #expect(state.connectionState == .scanning)
    }

    @Test("reset clears camera info")
    @MainActor func resetClearsCamera() {
        let state = makeAppState()
        let url = makeURL(query: [
            "token": "tok",
            "cam": "cam1",
            "base": "api.example.com"
        ])
        state.handleViewerURL(url)
        state.reset()
        #expect(state.cameraId == "")
        #expect(state.cameraName == "")
    }

    @Test("reset clears events and event types")
    @MainActor func resetClearsEvents() {
        let state = makeAppState()
        state.reset()
        #expect(state.events.isEmpty)
        #expect(state.availableEventTypes.isEmpty)
        #expect(state.activeEventTypes.isEmpty)
    }

    @Test("reset clears auth mode")
    @MainActor func resetClearsAuthMode() {
        let state = makeAppState()
        let url = makeURL(query: [
            "token": "tok",
            "cam": "cam1",
            "base": "api.example.com"
        ])
        state.handleViewerURL(url)
        #expect(state.authMode != nil)
        state.reset()
        #expect(state.authMode == nil)
    }
}

// MARK: - AppState Event Management Tests

@Suite("AppState Event Management")
struct AppStateEventManagementTests {

    @Test("configureQRCode sets connecting state with empty events")
    @MainActor func configureQRCodeState() {
        let state = makeAppState()
        state.configureQRCode(token: "tok", cameraId: "cam1", baseUrl: "https://api.example.com")
        #expect(state.connectionState == .connecting)
        #expect(state.events.isEmpty)
    }

    @Test("applyEventFilter updates activeEventTypes")
    @MainActor func applyFilter() {
        let state = makeAppState()
        let types = ["een.motionDetectionEvent.v1", "een.cameraOnlineEvent.v1"]
        state.applyEventFilter(types)
        #expect(state.activeEventTypes == types)
    }

    @Test("applyEventFilter clears events")
    @MainActor func applyFilterClearsEvents() {
        let state = makeAppState()
        state.applyEventFilter(["een.motionDetectionEvent.v1"])
        #expect(state.events.isEmpty)
    }

    @Test("applyEventFilter updates historyDuration")
    @MainActor func applyFilterDuration() {
        let state = makeAppState()
        state.applyEventFilter(["een.motionDetectionEvent.v1"], duration: 7200)
        #expect(state.historyDuration == 7200)
    }

    @Test("applyEventFilter without duration keeps existing")
    @MainActor func applyFilterKeepsDuration() {
        let state = makeAppState()
        let original = state.historyDuration
        state.applyEventFilter(["een.motionDetectionEvent.v1"])
        #expect(state.historyDuration == original)
    }

    @Test("refreshHistory clears events list")
    @MainActor func refreshClearsEvents() {
        let state = makeAppState()
        state.refreshHistory()
        #expect(state.events.isEmpty)
    }
}

// MARK: - Token Countdown Calculation Tests

@Suite("Token Countdown Calculations")
struct TokenCountdownTests {

    @Test("timeString formats days and hours")
    func formatDaysHours() {
        #expect(timeString(for: 90000) == "1d 1h")  // 1 day + 1 hour
    }

    @Test("timeString formats hours and minutes")
    func formatHoursMinutes() {
        #expect(timeString(for: 3661) == "1h 01m")
    }

    @Test("timeString formats minutes and seconds")
    func formatMinutesSeconds() {
        #expect(timeString(for: 125) == "2:05")
    }

    @Test("timeString formats zero")
    func formatZero() {
        #expect(timeString(for: 0) == "0:00")
    }

    @Test("progress is 1.0 when full")
    func progressFull() {
        #expect(progress(remaining: 3600, total: 3600) == 1.0)
    }

    @Test("progress is 0.5 at midpoint")
    func progressHalf() {
        #expect(progress(remaining: 1800, total: 3600) == 0.5)
    }

    @Test("progress is 0 when expired")
    func progressExpired() {
        #expect(progress(remaining: 0, total: 3600) == 0.0)
    }

    @Test("progress is 0 when total is 0")
    func progressZeroTotal() {
        #expect(progress(remaining: 100, total: 0) == 0.0)
    }

    @Test("bar color is green above 15 minutes")
    func barColorGreen() {
        #expect(barColorName(remaining: 901) == "green")
    }

    @Test("bar color is orange between 5 and 15 minutes")
    func barColorOrange() {
        #expect(barColorName(remaining: 600) == "orange")
        #expect(barColorName(remaining: 300) == "orange")
    }

    @Test("bar color is red below 5 minutes")
    func barColorRed() {
        #expect(barColorName(remaining: 299) == "red")
        #expect(barColorName(remaining: 0) == "red")
    }
}

// MARK: - ConnectionState Tests

@Suite("ConnectionState")
struct ConnectionStateTests {

    @Test("ConnectionState equality")
    func equality() {
        #expect(ConnectionState.scanning == .scanning)
        #expect(ConnectionState.connecting == .connecting)
        #expect(ConnectionState.live == .live)
        #expect(ConnectionState.expired == .expired)
        #expect(ConnectionState.error("A") == .error("A"))
        #expect(ConnectionState.error("A") != .error("B"))
        #expect(ConnectionState.scanning != .connecting)
    }
}
