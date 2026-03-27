//
//  CDSurveySection.swift
//  Agricultural_Survey
//

import Foundation
import CoreData

// Represents a specific section or grouping of questions within a survey response
@objc(CDSurveySection)
public class CDSurveySection: NSManagedObject {
    
    // Unique identifier for this specific section instance
    @NSManaged public var id: UUID?
    
    // The identifier that maps this section to the survey template (e.g., "crop_details" or "farmer_info")
    @NSManaged public var sectionKey: String
    
    // Used to track the order or index if a section is repeated multiple times
    @NSManaged public var repetitionIndex: Int64
    
    // Relationship linking this section back to its parent survey response
    @NSManaged public var survey: CDSurveyResponse?
    
    // One-to-many relationship containing all individual answers belonging to this section
    @NSManaged public var answers: NSSet?
    
    // MARK: - Computed Property
    
    // A helper property that converts the unordered NSSet of answers into a sorted array
    public var answersList: [CDAnswer] {
        // Safely casts the NSSet to a Swift Set of CDAnswer objects
        let set = answers as? Set<CDAnswer> ?? []
        
        // Returns the answers sorted alphabetically by their unique key for consistent UI display
        return set.sorted { $0.key < $1.key }
    }
}
