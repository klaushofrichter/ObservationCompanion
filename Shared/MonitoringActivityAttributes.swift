#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct MonitoringActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let cameraName: String
        let latestEventEmoji: String
        let latestEventDescription: String
        let eventCount: Int
        let lastEventTimestamp: Date?
        let latestEventId: String?
    }
}
#endif
