//
//  AnswerValue.swift
//  SurveySyncEngineIOS
//

import Foundation

/// A high-level enum using associated values to represent the various types of data a survey question can capture.
/// This acts as the Swift equivalent to a Kotlin 'sealed class'.
public enum AnswerValue {
    // Standard open-ended text response
    case text(String)
    
    // Numeric input (e.g., farm size, crop yield)
    case number(Double)
    
    // True/False or Yes/No toggle
    case bool(Bool)
    
    // A single GPS point with latitude, longitude, and horizontal accuracy
    case gpsCoordinate(lat: Double, lng: Double, accuracyMeters: Float)
    
    // A list of selected strings for checkbox/multi-select questions
    case multiChoice([String])
    
    // Explicitly indicates the user saw the question but chose not to answer
    case skipped
    
    // A collection of points defining a geographical area (e.g., a field boundary)
    case gpsBoundary([GpsPoint])
}

extension AnswerValue: Codable {
    // Defines the keys used for JSON serialization and deserialization
    private enum CodingKeys: String, CodingKey {
        case type, value, lat, lng, accuracy
    }

    // MARK: - Decoding (JSON -> Swift)
    /// Custom initializer to recreate the specific enum case based on a "type" field in the JSON.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "TEXT":
            self = .text(try container.decode(String.self, forKey: .value))
        case "NUMBER":
            self = .number(try container.decode(Double.self, forKey: .value))
        case "BOOL":
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case "GPS":
            self = .gpsCoordinate(
                lat: try container.decode(Double.self, forKey: .lat),
                lng: try container.decode(Double.self, forKey: .lng),
                // Ensures the accuracy is decoded as a Float to match the enum definition
                accuracyMeters: try container.decode(Float.self, forKey: .accuracy)
            )
        case "MULTI":
            self = .multiChoice(try container.decode([String].self, forKey: .value))
        case "SKIPPED":
            self = .skipped
        default:
            // Fallback to skipped for any unrecognized types to prevent decoding crashes
            self = .skipped
        }
    }

    // MARK: - Encoding (Swift -> JSON)
    /// Custom encoding logic to flatten the enum cases into a standardized JSON structure.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let val):
            try container.encode("TEXT", forKey: .type)
            try container.encode(val, forKey: .value)
        case .number(let val):
            try container.encode("NUMBER", forKey: .type)
            try container.encode(val, forKey: .value)
        case .bool(let val):
            try container.encode("BOOL", forKey: .type)
            try container.encode(val, forKey: .value)
        case .gpsCoordinate(let lat, let lng, let acc):
            try container.encode("GPS", forKey: .type)
            try container.encode(lat, forKey: .lat)
            try container.encode(lng, forKey: .lng)
            try container.encode(acc, forKey: .accuracy)
        case .multiChoice(let selected):
            try container.encode("MULTI", forKey: .type)
            try container.encode(selected, forKey: .value)
        case .skipped:
            try container.encode("SKIPPED", forKey: .type)
        case .gpsBoundary(_):
            // Currently handled elsewhere (e.g., via SurveyMapper's JSON encoding logic)
            break
        }
    }
}
