import Foundation

enum EventTypeHash {
    private static let chars = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    static func hash(_ eventType: String) -> String {
        var h: UInt32 = 5381
        for scalar in eventType.unicodeScalars {
            h = ((h &<< 5) &+ h &+ UInt32(scalar.value))
        }
        var result = ""
        var remaining = h
        for _ in 0..<3 {
            result.append(chars[Int(remaining % 62)])
            remaining /= 62
        }
        return result
    }

    static func buildLookup(_ eventTypes: [String]) -> [String: String] {
        var lookup: [String: String] = [:]
        for type in eventTypes {
            lookup[hash(type)] = type
        }
        return lookup
    }

    static func resolve(hashString: String, lookup: [String: String]) -> [String] {
        hashString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { lookup[$0] }
    }

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func eventDescription(type: String, startTimestamp: String) -> String {
        var desc = displayName(type)
        if !startTimestamp.isEmpty,
           let idx = startTimestamp.firstIndex(of: "T") {
            let time = String(startTimestamp[startTimestamp.index(after: idx)...])
                .replacingOccurrences(of: "Z", with: "")
            desc += " @ \(time)"
        }
        return desc
    }

    static func displayName(_ eventType: String) -> String {
        var name = eventType
        if name.hasPrefix("een.") { name = String(name.dropFirst(4)) }
        if name.hasSuffix(".v1") { name = String(name.dropLast(3)) }
        if name.hasSuffix("Event") { name = String(name.dropLast(5)) }

        var result = ""
        for char in name {
            if char.isUppercase && !result.isEmpty {
                result.append(" ")
            }
            result.append(char)
        }

        return result.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
