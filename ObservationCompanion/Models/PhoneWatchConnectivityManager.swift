import Foundation
import UIKit
import WatchConnectivity
import Combine
import EENSwiftToolkit

class PhoneWatchConnectivityManager: NSObject, ObservableObject {
    private var session: WCSession?
    private var cancellables = Set<AnyCancellable>()
    private var previousEventIds = Set<UUID>()
    private weak var appState: AppState?
    private var prewarmCameraId: String?
    private var activeEventTypes: Set<String> = []

    private var isActivated = false
    private var lastSentCameraName: String?

    func activate(appState: AppState) {
        guard !isActivated else { return }
        isActivated = true
        self.appState = appState
        guard WCSession.isSupported() else { return }
        session = WCSession.default
        session?.delegate = self
        session?.activate()

        appState.$events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] events in
                guard let self = self, let appState = self.appState else { return }
                self.handleEventsUpdate(events, cameraName: appState.cameraName, cameraId: appState.cameraId)
            }
            .store(in: &cancellables)

        appState.$cameraName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.handleCameraChange(cameraName: name)
            }
            .store(in: &cancellables)

        appState.$activeEventTypes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] types in
                self?.handleFilterChange(types: types)
            }
            .store(in: &cancellables)
    }

    private func handleEventsUpdate(_ events: [CameraEvent], cameraName: String, cameraId: String) {
        // Don't send anything until the camera is fully loaded
        guard !cameraName.isEmpty, !cameraId.isEmpty else { return }

        // Detect camera change when we have events and camera name is ready
        if !events.isEmpty && cameraName != lastSentCameraName {
            lastSentCameraName = cameraName
            handleCameraChange(cameraName: cameraName)
        }

        let currentIds = Set(events.map(\.id))
        let newEvents = events.filter { !previousEventIds.contains($0.id) }
        previousEventIds = currentIds

        guard let session = session, session.isReachable else { return }

        for event in newEvents {
            if !activeEventTypes.isEmpty && !activeEventTypes.contains(event.type) {
                continue
            }
            let isLive = event.timestamp.timeIntervalSinceNow > -30
            let boxes = event.boundingBoxes.map {
                WatchBoundingBox(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
            }
            var message = WatchEvent(
                eventType: event.type,
                typeEmoji: event.typeEmoji,
                typeName: EventTypeHash.displayName(event.type),
                description: event.description,
                cameraName: cameraName,
                cameraId: cameraId,
                timestamp: event.timestamp,
                boundingBoxes: boxes,
                eevaReason: event.eevaReason,
                confidences: event.confidences
            ).dictionary
            message["isLive"] = isLive
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }

        // Prewarm image pipeline with an older event
        if prewarmCameraId != cameraId, !cameraId.isEmpty {
            let oldEvent = events.first { $0.timestamp.timeIntervalSinceNow < -600 }
            if let event = oldEvent {
                prewarmCameraId = cameraId
                prewarmImage(cameraId: cameraId, timestamp: event.timestamp)
            }
        }
    }

    private func handleFilterChange(types: [String]) {
        let newFilter = Set(types)
        guard newFilter != activeEventTypes else { return }
        activeEventTypes = newFilter
        guard let session = session, session.isReachable else { return }
        session.sendMessage(["filterChange": true, "activeTypes": types], replyHandler: nil, errorHandler: nil)
    }

    private func handleSyncRequest() {
        guard let appState = appState, let session = session, session.isReachable else { return }
        let cameraName = appState.cameraName
        let cameraId = appState.cameraId
        let events = appState.events

        // Don't sync if the phone hasn't loaded a camera yet
        guard !cameraName.isEmpty, !cameraId.isEmpty else { return }

        // Send camera change to clear Watch state and set correct camera name
        session.sendMessage(["cameraChange": true, "cameraName": cameraName], replyHandler: nil, errorHandler: nil)
        try? session.updateApplicationContext(["cameraName": cameraName])
        lastSentCameraName = cameraName

        // Send current events
        for event in events {
            if !activeEventTypes.isEmpty && !activeEventTypes.contains(event.type) {
                continue
            }
            let boxes = event.boundingBoxes.map {
                WatchBoundingBox(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
            }
            var message = WatchEvent(
                eventType: event.type,
                typeEmoji: event.typeEmoji,
                typeName: EventTypeHash.displayName(event.type),
                description: event.description,
                cameraName: cameraName,
                cameraId: cameraId,
                timestamp: event.timestamp,
                boundingBoxes: boxes,
                eevaReason: event.eevaReason,
                confidences: event.confidences
            ).dictionary
            message["isLive"] = false
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }

        // Mark these as known so they don't get re-sent
        previousEventIds = Set(events.map(\.id))
    }

    private func handleCameraChange(cameraName: String) {
        guard !cameraName.isEmpty else { return }
        guard let session = session, session.activationState == .activated else { return }
        try? session.updateApplicationContext(["cameraName": cameraName])
        previousEventIds.removeAll()
        prewarmCameraId = nil
        if session.isReachable {
            session.sendMessage(["cameraChange": true, "cameraName": cameraName], replyHandler: nil, errorHandler: nil)
        }
    }


    private func prewarmImage(cameraId: String, timestamp: Date) {
        guard let appState = appState else { return }
        Task {
            var params = GetRecordedImageParams()
            params.timestampGte = formatTimestamp(timestamp)
            params.type = .preview
            params.targetWidth = 312
            _ = try? await appState.toolkit.media.getRecordedImage(deviceId: cameraId, params: params)
        }
    }

    private func handleImageRequest(_ message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let cameraId = message["cameraId"] as? String,
              let timestampInterval = message["timestamp"] as? TimeInterval,
              let appState = appState else {
            replyHandler(["error": "Missing parameters"])
            return
        }

        let timestamp = Date(timeIntervalSince1970: timestampInterval)
        Task {
            do {
                var params = GetRecordedImageParams()
                params.timestampGte = formatTimestamp(timestamp)
                params.type = .preview
                params.targetWidth = 312
                let result = try await appState.toolkit.media.getRecordedImage(deviceId: cameraId, params: params)
                replyHandler(["imageData": result.imageData])
            } catch {
                replyHandler(["error": error.localizedDescription])
            }
        }
    }

    private func handleLiveImageRequest(_ message: [String: Any]) {
        guard let appState = appState else {
            session?.sendMessage(["liveImageError": "No camera"], replyHandler: nil, errorHandler: nil)
            return
        }

        let cameraId = (message["cameraId"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? appState.cameraId
        guard !cameraId.isEmpty else {
            session?.sendMessage(["liveImageError": "No camera"], replyHandler: nil, errorHandler: nil)
            return
        }
        Task {
            do {
                let params = GetLiveImageParams(deviceId: cameraId, type: "preview")
                let result = try await appState.toolkit.media.getLiveImage(params: params)
                let resized = Self.resizeImageData(result.imageData, targetSize: 50_000)
                session?.sendMessageData(resized, replyHandler: nil, errorHandler: nil)
            } catch {
                session?.sendMessage(["liveImageError": error.localizedDescription], replyHandler: nil, errorHandler: nil)
            }
        }
    }

    private static func resizeImageData(_ data: Data, targetSize: Int) -> Data {
        guard let image = UIImage(data: data) else { return data }
        if data.count <= targetSize { return data }

        // Try progressively smaller sizes and lower quality until under target
        let widths: [CGFloat] = [312, 250, 200, 160]
        let qualities: [CGFloat] = [0.5, 0.3, 0.2]

        for width in widths {
            let scale = min(1.0, width / image.size.width)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            for quality in qualities {
                let resized = renderer.jpegData(withCompressionQuality: quality) { context in
                    image.draw(in: CGRect(origin: .zero, size: newSize))
                }
                if resized.count <= targetSize {
                    return resized
                }
            }
        }
        // Last resort: smallest size, lowest quality
        let smallSize = CGSize(width: 160, height: image.size.height * (160 / image.size.width))
        let renderer = UIGraphicsImageRenderer(size: smallSize)
        return renderer.jpegData(withCompressionQuality: 0.1) { context in
            image.draw(in: CGRect(origin: .zero, size: smallSize))
        }
    }
}

extension PhoneWatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        _ = error
        if activationState == .activated {
            Task { @MainActor in
                if let name = appState?.cameraName, !name.isEmpty {
                    handleCameraChange(cameraName: name)
                }
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let request = message["request"] as? String
        if request == "liveImage" {
            Task { @MainActor in
                handleLiveImageRequest(message)
            }
        } else if request == "sync" {
            Task { @MainActor in
                handleSyncRequest()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let request = message["request"] as? String
        if request == "recordedImage" {
            Task { @MainActor in
                handleImageRequest(message, replyHandler: replyHandler)
            }
        } else {
            replyHandler([:])
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
