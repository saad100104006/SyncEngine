//
//  AnswerValue.swift
//  SurveySyncEngineIOS
//
import Foundation

public enum AnswerValue {
    case text(String)
    case number(Double)
    case bool(Bool)
    case gpsCoordinate(lat: Double, lng: Double, accuracyMeters: Float)
    case multiChoice([String])
    case skipped
    /// Ordered polygon of GPS vertices defining a field boundary (≥3 for valid polygon).
    case gpsBoundary([GpsPoint])
}

extension AnswerValue: Codable {
    private enum CodingKeys: String, CodingKey { case type, value, lat, lng, accuracy, vertices }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "TEXT":         self = .text(try c.decode(String.self, forKey: .value))
        case "NUMBER":       self = .number(try c.decode(Double.self, forKey: .value))
        case "BOOL":         self = .bool(try c.decode(Bool.self, forKey: .value))
        case "GPS":          self = .gpsCoordinate(lat: try c.decode(Double.self, forKey: .lat),
                                                    lng: try c.decode(Double.self, forKey: .lng),
                                                    accuracyMeters: try c.decode(Float.self, forKey: .accuracy))
        case "GPS_BOUNDARY": self = .gpsBoundary(try c.decode([GpsPoint].self, forKey: .vertices))
        case "MULTI":        self = .multiChoice(try c.decode([String].self, forKey: .value))
        default:             self = .skipped
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let v):
            try c.encode("TEXT", forKey: .type); try c.encode(v, forKey: .value)
        case .number(let v):
            try c.encode("NUMBER", forKey: .type); try c.encode(v, forKey: .value)
        case .bool(let v):
            try c.encode("BOOL", forKey: .type); try c.encode(v, forKey: .value)
        case .gpsCoordinate(let lat, let lng, let acc):
            try c.encode("GPS", forKey: .type)
            try c.encode(lat, forKey: .lat); try c.encode(lng, forKey: .lng); try c.encode(acc, forKey: .accuracy)
        case .gpsBoundary(let pts):
            // FIX Bug 3: was `case .gpsBoundary(_): break` which produced an empty
            // JSON object {} — the GPS boundary data was silently lost on every
            // Codable round-trip. Fix: encode the vertices array under the "vertices"
            // key with the GPS_BOUNDARY type discriminator, matching the decode path.
            try c.encode("GPS_BOUNDARY", forKey: .type)
            try c.encode(pts, forKey: .vertices)
        case .multiChoice(let s):
            try c.encode("MULTI", forKey: .type); try c.encode(s, forKey: .value)
        case .skipped:
            try c.encode("SKIPPED", forKey: .type)
        }
    }
}

extension AnswerValue: Equatable {
    public static func == (lhs: AnswerValue, rhs: AnswerValue) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)):           return a == b
        case (.number(let a), .number(let b)):       return a == b
        case (.bool(let a), .bool(let b)):           return a == b
        case (.multiChoice(let a), .multiChoice(let b)): return a == b
        case (.skipped, .skipped):                   return true
        case (.gpsCoordinate(let la,let lo,let ac), .gpsCoordinate(let lb,let ob,let bc)):
            return la==lb && lo==ob && ac==bc
        case (.gpsBoundary(let a), .gpsBoundary(let b)): return a == b
        default: return false
        }
    }
}
