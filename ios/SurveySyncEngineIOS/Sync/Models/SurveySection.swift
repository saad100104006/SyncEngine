//
//  SurveySection.swift
//  Agricultural_Survey
//
import Foundation

/// A recursive data structure used to represent grouped questions within a survey.
/// This model is designed to handle hierarchical data, such as a farm that contains multiple sub-plots.
public struct SurveySection: Codable, Identifiable {
    // Unique identifier for the specific section instance
    public let id: UUID
    
    // The display name or header for the section (e.g., "Farmer Information" or "Crop History")
    public let title: String
    
    // A dictionary mapping unique question identifiers to their corresponding string-based responses
    public let answers: [String: String] // Question Key : Answer Value
    
    // An optional array of nested SurveySection objects, allowing for infinite levels of grouping
    // or repeating data sets (e.g., a "Farm" section containing several "Plot" sub-sections).
    public let subSections: [SurveySection]?
    
    /// Initializes a new survey section with support for optional nesting.
    public init(id: UUID = UUID(), title: String, answers: [String: String], subSections: [SurveySection]? = nil) {
        self.id = id
        self.title = title
        self.answers = answers
        self.subSections = subSections
    }
}
