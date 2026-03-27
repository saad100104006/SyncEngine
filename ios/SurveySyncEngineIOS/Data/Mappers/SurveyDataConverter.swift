//
//  SurveyDataConverter.swift
//  SurveySyncEngineIOS
//
//

import Foundation

/// A utility structure responsible for transforming survey data between domain models and serializable formats.
public struct SurveyDataConverter {
    // Reusable JSON encoder to handle the conversion from Swift types to JSON data
    private static let encoder = JSONEncoder()
    // Reusable JSON decoder to handle the conversion from JSON data back to Swift types
    private static let decoder = JSONDecoder()

    // MARK: - Answer Map Conversion
    // These methods facilitate storing a complex dictionary of answers as a single string (often for database storage).
    
    /// Encodes a dictionary of answer values into a JSON-formatted string.
    public static func answersToJson(_ answers: [String: AnswerValue]) -> String {
        // Attempt to encode the dictionary; return an empty JSON object string if encoding fails
        guard let data = try? encoder.encode(answers) else { return "{}" }
        // Convert the encoded data into a UTF-8 string
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Decodes a JSON-formatted string back into a dictionary of [String: AnswerValue].
    public static func jsonToAnswers(_ json: String) -> [String: AnswerValue] {
        // Ensure the string can be converted to UTF-8 data
        guard let data = json.data(using: .utf8) else { return [:] }
        // Attempt to decode the data into the expected dictionary format; return an empty dictionary on failure
        return (try? decoder.decode([String: AnswerValue].self, from: data)) ?? [:]
    }

    // MARK: - Status Conversions
    // These helpers bridge the gap between raw string storage in Core Data and the type-safe SyncStatus enum.

    /// Converts a SyncStatus enum case into its corresponding string representation.
    public static func syncStatusToString(_ status: SyncStatus) -> String {
        return status.rawValue
    }

    /// Converts a string identifier back into a SyncStatus enum case.
    public static func stringToSyncStatus(_ string: String) -> SyncStatus {
        // Attempts to initialize the enum from the string; defaults to .pending if the string is unrecognized
        return SyncStatus(rawValue: string) ?? .pending
    }
}
