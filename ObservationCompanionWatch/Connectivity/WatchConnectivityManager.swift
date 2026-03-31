import Combine
import Foundation
import WatchConnectivity
import WatchKit

class WatchConnectivityManager: NSObject, ObservableObject {
    @Published var events: [WatchEvent] = []
    @Published var cameraName: String = ""
    @Published var isConnected: Bool = false
    @Published var cameraChangeCount: Int = 0
    @Published var liveImageData: Data?
    @Published var liveImageError: String?

    private static let maxEvents = 50
    private var liveImageCompletion: ((Data?) -> Void)?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func addEvent(_ event: WatchEvent, isLive: Bool) {
        // If camera changed, clear old events
        if !event.cameraId.isEmpty && !events.isEmpty && events.first?.cameraId != event.cameraId {
            events.removeAll()
            cameraChangeCount += 1
        }

        events.append(event)
        events.sort { $0.timestamp > $1.timestamp }
        if events.count > Self.maxEvents {
            events = Array(events.prefix(Self.maxEvents))
        }
        if !event.cameraName.isEmpty {
            cameraName = event.cameraName
        }
        if isLive {
            WKInterfaceDevice.current().play(.notification)
        }
    }

    func requestLiveImage(completion: @escaping (Data?) -> Void) {
        guard WCSession.default.isReachable else {
            completion(nil)
            return
        }
        let cameraId = events.first?.cameraId ?? ""
        liveImageCompletion = completion
        let message: [String: Any] = ["request": "liveImage", "cameraId": cameraId]
        WCSession.default.sendMessage(message, replyHandler: nil) { [weak self] error in
            Task { @MainActor in
                self?.liveImageCompletion?(nil)
                self?.liveImageCompletion = nil
            }
        }
    }

    func requestImage(for event: WatchEvent, completion: @escaping (Data?) -> Void) {
        guard WCSession.default.isReachable else {
            completion(nil)
            return
        }
        let message: [String: Any] = [
            "request": "recordedImage",
            "cameraId": event.cameraId,
            "timestamp": event.timestamp.timeIntervalSince1970
        ]
        WCSession.default.sendMessage(message, replyHandler: { reply in
            if let imageData = reply["imageData"] as? Data {
                completion(imageData)
            } else {
                completion(nil)
            }
        }, errorHandler: { _ in
            completion(nil)
        })
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            isConnected = activationState == .activated
            if activationState == .activated, session.isReachable {
                requestSync()
            }
        }
        _ = error
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in
            liveImageCompletion?(messageData)
            liveImageCompletion = nil
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let errorMsg = message["liveImageError"] as? String {
            Task { @MainActor in
                liveImageCompletion?(nil)
                liveImageCompletion = nil
            }
            _ = errorMsg
            return
        }

        if message["cameraChange"] as? Bool == true {
            Task { @MainActor in
                if let name = message["cameraName"] as? String {
                    cameraName = name
                }
                events.removeAll()
                cameraChangeCount += 1
            }
            return
        }
        if message["filterChange"] as? Bool == true {
            let activeTypes = Set(message["activeTypes"] as? [String] ?? [])
            Task { @MainActor in
                if !activeTypes.isEmpty {
                    events.removeAll { !activeTypes.contains($0.eventType) }
                }
            }
            return
        }
        let isLive = message["isLive"] as? Bool ?? false
        Task { @MainActor in
            guard let event = WatchEvent(dictionary: message) else { return }
            addEvent(event, isLive: isLive)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            if let name = applicationContext["cameraName"] as? String {
                cameraName = name
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isConnected = session.isReachable
            if session.isReachable {
                requestSync()
            }
        }
    }

    private func requestSync() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["request": "sync"], replyHandler: nil, errorHandler: nil)
    }
}
