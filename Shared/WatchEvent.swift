import Foundation

struct WatchBoundingBox: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var dictionary: [String: Any] {
        ["x": x, "y": y, "width": width, "height": height]
    }

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    init?(dictionary: [String: Any]) {
        guard let x = dictionary["x"] as? Double,
              let y = dictionary["y"] as? Double,
              let width = dictionary["width"] as? Double,
              let height = dictionary["height"] as? Double else { return nil }
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

struct WatchEvent: Codable, Identifiable {
    let id: UUID
    let eventType: String
    let typeEmoji: String
    let typeName: String
    let description: String
    let cameraName: String
    let cameraId: String
    let timestamp: Date
    let boundingBoxes: [WatchBoundingBox]
    let eevaReason: String?
    let confidences: [Double]

    var confidenceText: String? {
        guard !confidences.isEmpty else { return nil }
        if confidences.count == 1 {
            return String(format: "%.0f%% Confidence", confidences[0] * 100)
        }
        let lo = confidences.min()!
        let hi = confidences.max()!
        return String(format: "%.0f%% to %.0f%% Confidence", lo * 100, hi * 100)
    }

    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString,
            "eventType": eventType,
            "typeEmoji": typeEmoji,
            "typeName": typeName,
            "description": description,
            "cameraName": cameraName,
            "cameraId": cameraId,
            "timestamp": timestamp.timeIntervalSince1970,
            "boundingBoxes": boundingBoxes.map { $0.dictionary }
        ]
        if let eevaReason { dict["eevaReason"] = eevaReason }
        if !confidences.isEmpty { dict["confidences"] = confidences }
        return dict
    }

    init(id: UUID = UUID(), eventType: String, typeEmoji: String, typeName: String, description: String, cameraName: String, cameraId: String, timestamp: Date, boundingBoxes: [WatchBoundingBox] = [], eevaReason: String? = nil, confidences: [Double] = []) {
        self.id = id
        self.eventType = eventType
        self.typeEmoji = typeEmoji
        self.typeName = typeName
        self.description = description
        self.cameraName = cameraName
        self.cameraId = cameraId
        self.timestamp = timestamp
        self.boundingBoxes = boundingBoxes
        self.eevaReason = eevaReason
        self.confidences = confidences
    }

    init?(dictionary: [String: Any]) {
        guard let idString = dictionary["id"] as? String,
              let id = UUID(uuidString: idString),
              let eventType = dictionary["eventType"] as? String,
              let typeEmoji = dictionary["typeEmoji"] as? String,
              let typeName = dictionary["typeName"] as? String,
              let description = dictionary["description"] as? String,
              let cameraName = dictionary["cameraName"] as? String,
              let cameraId = dictionary["cameraId"] as? String,
              let timestampInterval = dictionary["timestamp"] as? TimeInterval else {
            return nil
        }
        self.id = id
        self.eventType = eventType
        self.typeEmoji = typeEmoji
        self.typeName = typeName
        self.description = description
        self.cameraName = cameraName
        self.cameraId = cameraId
        self.timestamp = Date(timeIntervalSince1970: timestampInterval)
        if let boxDicts = dictionary["boundingBoxes"] as? [[String: Any]] {
            self.boundingBoxes = boxDicts.compactMap { WatchBoundingBox(dictionary: $0) }
        } else {
            self.boundingBoxes = []
        }
        self.eevaReason = dictionary["eevaReason"] as? String
        self.confidences = dictionary["confidences"] as? [Double] ?? []
    }
}
