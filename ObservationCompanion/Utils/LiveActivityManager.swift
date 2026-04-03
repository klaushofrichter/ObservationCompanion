#if canImport(ActivityKit)
import ActivityKit
import Foundation
import os

private let logger = Logger(subsystem: "skylar.ObservationCompanion", category: "LiveActivity")

@MainActor
class LiveActivityManager {
    static let staleDuration: TimeInterval = 120

    private var currentActivity: Activity<MonitoringActivityAttributes>?
    private(set) var isDismissed = false

    func startMonitoring(cameraName: String) {
        isDismissed = false

        // If already running, skip
        if currentActivity != nil {
            return
        }

        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            logger.warning("Activities not enabled")
            return
        }

        let attributes = MonitoringActivityAttributes()
        let initialState = MonitoringActivityAttributes.ContentState(
            cameraName: cameraName,
            latestEventEmoji: "",
            latestEventSymbol: "",
            latestEventDescription: "Connecting to event stream...",
            eventCount: 0,
            lastEventTimestamp: nil,
            latestEventId: nil
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date(timeIntervalSinceNow: Self.staleDuration)),
                pushType: nil
            )
            currentActivity = activity
            logger.info("Started activity: \(activity.id)")
        } catch {
            logger.error("Failed to start: \(error)")
        }
    }

    func updateWithEvent(cameraName: String,
                         emoji: String, symbol: String,
                         description: String, eventCount: Int,
                         timestamp: Date? = nil, eventId: String? = nil) {
        guard let activity = currentActivity else {
            logger.warning("updateWithEvent: no currentActivity")
            return
        }
        guard !isDismissed else { return }

        logger.info("Updating activity: symbol=\(symbol) count=\(eventCount)")
        NSLog("[LiveActivity] Updating: symbol=%@ count=%d", symbol, eventCount)

        let updatedState = MonitoringActivityAttributes.ContentState(
            cameraName: cameraName,
            latestEventEmoji: emoji,
            latestEventSymbol: symbol,
            latestEventDescription: description,
            eventCount: eventCount,
            lastEventTimestamp: timestamp,
            latestEventId: eventId
        )

        Task {
            await activity.update(
                ActivityContent(state: updatedState, staleDate: Date(timeIntervalSinceNow: Self.staleDuration))
            )
            NSLog("[LiveActivity] Update completed, activityState=%@", String(describing: activity.activityState))
        }
    }

    func dismiss() {
        guard let activity = currentActivity else { return }
        isDismissed = true
        currentActivity = nil

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        logger.info("Dismissed via user action")
    }

    func undismiss(cameraName: String) {
        guard isDismissed else { return }
        isDismissed = false
        startMonitoring(cameraName: cameraName)
    }

    func endMonitoring() {
        guard let activity = currentActivity else { return }
        currentActivity = nil

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
#endif
