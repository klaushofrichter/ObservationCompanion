import Foundation
import EENApiToolkit

struct BoundingBox: Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct CameraEvent: Identifiable, Equatable {
    let id: UUID
    let eventId: String?
    let timestamp: Date
    let type: String
    let actorId: String
    let description: String
    let raw: String
    let boundingBoxes: [BoundingBox]
    let eevaReason: String?
    let confidences: [Double]

    init(type: String, actorId: String, description: String, raw: String = "", timestamp: Date = Date(), eventId: String? = nil, boundingBoxes: [BoundingBox] = [], eevaReason: String? = nil, confidences: [Double] = []) {
        self.id = UUID()
        self.eventId = eventId
        self.timestamp = timestamp
        self.type = type
        self.actorId = actorId
        self.description = description
        self.raw = raw
        self.boundingBoxes = boundingBoxes
        self.eevaReason = eevaReason
        self.confidences = confidences
    }

    /// Extract bounding boxes from event data items.
    /// The EEN API returns `een.objectDetection.v1` data items with a
    /// `boundingBox` array of `[x1, y1, x2, y2]` in normalized 0-1 coordinates.
    static func extractBoundingBoxes(from data: [EventData]) -> [BoundingBox] {
        var boxes: [BoundingBox] = []
        for eventData in data {
            guard eventData.type == "een.objectDetection.v1",
                  let props = eventData.additionalProperties,
                  let bbox = props["boundingBox"],
                  case .array(let coords) = bbox,
                  coords.count == 4 else { continue }
            let values = coords.compactMap { doubleValue($0) }
            guard values.count == 4 else { continue }
            let (x1, y1, x2, y2) = (values[0], values[1], values[2], values[3])
            boxes.append(BoundingBox(x: x1, y: y1, width: x2 - x1, height: y2 - y1))
        }
        return boxes
    }

    /// Extract the EEVA reason from an `een.eevaAttributes.v1` data item, if present.
    static func extractEevaReason(from data: [EventData]) -> String? {
        for eventData in data {
            guard eventData.type == "een.eevaAttributes.v1",
                  let props = eventData.additionalProperties,
                  let reason = props["reason"],
                  case .string(let value) = reason,
                  !value.isEmpty else { continue }
            return value
        }
        return nil
    }

    /// Extract confidence values from `een.objectClassification.v1` data items.
    static func extractConfidences(from data: [EventData]) -> [Double] {
        var values: [Double] = []
        for eventData in data {
            guard eventData.type == "een.objectClassification.v1",
                  let props = eventData.additionalProperties,
                  let conf = props["confidence"],
                  let value = doubleValue(conf) else { continue }
            values.append(value)
        }
        return values
    }

    /// Format confidence values for display.
    /// Shows bounding box count when there are multiple boxes.
    var confidenceText: String? {
        guard !confidences.isEmpty else { return nil }
        let boxCount = boundingBoxes.count
        let suffix = boxCount > 1 ? " (\(boxCount))" : ""
        let lo = confidences.min()!
        let hi = confidences.max()!
        if confidences.count == 1 || lo == hi {
            return String(format: "%.1f%% confidence", lo * 100) + suffix
        }
        return String(format: "%.1f%% to %.1f%% confidence", lo * 100, hi * 100) + suffix
    }

    private static func doubleValue(_ value: AnyCodable) -> Double? {
        switch value {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }

    nonisolated static func == (lhs: CameraEvent, rhs: CameraEvent) -> Bool {
        lhs.id == rhs.id
    }

    var typeEmoji: String {
        switch type {
        // Detection events
        case "een.motionDetectionEvent.v1":             return "👁️"
        case "een.motionInRegionDetectionEvent.v1":     return "🎯"
        case "een.personDetectionEvent.v1":             return "🧑"
        case "een.personMotionDetectionEvent.v1":       return "🚶"
        case "een.animalDetectionEvent.v1":             return "🐾"
        case "een.faceDetectionEvent.v1":               return "😀"
        case "een.vehicleDetectionEvent.v1":            return "🚗"
        case "een.vehicleMotionDetectionEvent.v1":      return "🚙"
        case "een.gunDetectionEvent.v1":                return "🔫"
        case "een.weaponDetectionEvent.v1":             return "🗡️"
        case "een.fallDetectionEvent.v1":               return "🤸"
        case "een.fireDetectionEvent.v1":               return "🔥"
        case "een.spillDetectionEvent.v1":              return "💧"
        case "een.crowdFormationDetectionEvent.v1":     return "👥"
        // Camera analytics
        case "een.tamperDetectionEvent.v1":             return "⚠️"
        case "een.loiterDetectionEvent.v1":             return "🕐"
        case "een.objectLineCrossEvent.v1":             return "➡️"
        case "een.objectLineCrossCountEvent.v1":        return "🔢"
        case "een.countedObjectLineCrossEvent.v1":      return "🔢"
        case "een.objectIntrusionEvent.v1":             return "🚧"
        case "een.objectRemovalEvent.v1":               return "📦"
        case "een.personTailgateEvent.v1":              return "🚪"
        case "een.ppeViolationEvent.v1":                return "🦺"
        // AI/Scene
        case "een.sceneLabelEvent.v1":                  return "🏷️"
        case "een.eevaQueryEvent.v1":                   return "🤖"
        // LPR & Fleet
        case "een.lprPlateReadEvent.v1":                return "🪪"
        case "een.fleetCodeRecognitionEvent.v1":        return "🚛"
        // Audio
        case "een.gunShotAudioDetectionEvent.v1":       return "💥"
        case "een.t3AlarmAudioDetectionEvent.v1":       return "🔔"
        case "een.t4AlarmAudioDetectionEvent.v1":       return "🔔"
        // POS
        case "een.posTransactionEvent.v1":              return "💳"
        // Device/System
        case "een.deviceCloudStatusUpdateEvent.v1":     return "☁️"
        case "een.deviceCloudConnectionStatusUpdateEvent.v1": return "🔌"
        case "een.edgeReportedDeviceStatusEvent.v1":    return "📡"
        case "een.deviceIOEvent.v1":                    return "⚡"
        case "een.deviceOperationEvent.v1":             return "🔧"
        case "een.ptzPositionUpdateEvent.v1":           return "🎥"
        // Sensor
        case "een.doorStatusEvent.v1":                  return "🚪"
        case "een.batteryLevelUpdateEvent.v1":          return "🔋"
        case "een.measurementThresholdStatusEvent.v1":  return "📊"
        case "een.thermalCameraThresholdStatusEvent.v1": return "🌡️"
        // Resource management
        case "een.layoutCreationEvent.v1":              return "📐"
        case "een.layoutUpdateEvent.v1":                return "📐"
        case "een.layoutDeletionEvent.v1":              return "📐"
        case "een.deviceCreationEvent.v1":              return "📹"
        case "een.deviceUpdateEvent.v1":                return "📹"
        case "een.deviceDeletionEvent.v1":              return "📹"
        case "een.userCreationEvent.v1":                return "👤"
        case "een.userUpdateEvent.v1":                  return "👤"
        case "een.userDeletionEvent.v1":                return "👤"
        case "een.accountCreationEvent.v1":             return "🏢"
        case "een.accountUpdateEvent.v1":               return "🏢"
        case "een.accountDeletionEvent.v1":             return "🏢"
        // Job
        case "een.jobCreationEvent.v1":                 return "📋"
        case "een.jobUpdateEvent.v1":                   return "📋"
        case "een.jobDeletionEvent.v1":                 return "📋"
        // Access control
        case "een.accessActivationEvent.v1":            return "🔑"
        // Safety/Protocol
        case "een.panicButtonEvent.v1":                 return "🆘"
        case "een.evacuateProtocolEvent.v1":            return "🏃‍♂️"
        case "een.holdProtocolEvent.v1":                return "✋"
        case "een.lockdownProtocolEvent.v1":            return "🔒"
        case "een.secureProtocolEvent.v1":              return "🛡️"
        case "een.shelterProtocolEvent.v1":             return "🏠"
        // Behavioral
        case "een.violenceDetectionEvent.v1":           return "👊"
        case "een.fightDetectionEvent.v1":              return "🥊"
        case "een.handsUpDetectionEvent.v1":            return "🙌"
        case "een.vapeDetectionEvent.v1":               return "🚬"
        // Fallback
        default:                                        return "📋"
        }
    }
}
