//
//  CDAnswer.swift
//  Agricultural_Survey
//

import Foundation
import CoreData

// Maps the Swift class to the Core Data model entity name
@objc(CDAnswer)
public class CDAnswer: NSManagedObject {
    
    // The unique identifier or dictionary key associated with the specific survey question
    @NSManaged public var key: String
    
    // Determines the data type of the answer (e.g., "text", "number", "gps") to dictate which value field to access
    @NSManaged public var answerTypeValue: String
    
    // Flattened storage for various data types.
    // Logic should ensure only the field corresponding to answerTypeValue is utilized.
    
    // Stores string-based responses or open-ended text
    @NSManaged public var textValue: String?
    
    // Stores numeric responses; ensure "Use Scalar Type" is enabled in the Data Model inspector
    @NSManaged public var numberValue: Double
    
    // Stores true/false toggle responses
    @NSManaged public var boolValue: Bool
    
    // Latitude coordinate for GPS-based survey answers
    @NSManaged public var lat: Double
    
    // Longitude coordinate for GPS-based survey answers
    @NSManaged public var lng: Double
    
    // Horizontal accuracy of the captured GPS coordinates in meters
    @NSManaged public var accuracy: Float
    
    // Binary data used for complex mapping or boundary-related survey inputs
    @NSManaged public var boundaryData: Data?
    
    // Stores multiple selected options; requires "Transformable" type in Core Data with a secure transformer
    @NSManaged public var multiChoiceValues: [String]?
    
    // Defines the inverse relationship linking this answer back to its parent survey section
    @NSManaged public var section: CDSurveySection?
}
