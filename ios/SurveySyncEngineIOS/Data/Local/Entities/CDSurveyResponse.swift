//
//  CDSurveyResponse.swift
//  Agricultural_Survey
//
//
import Foundation
import CoreData

// Main Core Data entity representing a complete survey submission for a farmer
@objc(CDSurveyResponse)
public class CDSurveyResponse: NSManagedObject {
    
    // MARK: - Standard Attributes
    
    // Unique identifier for this specific survey response instance
    @NSManaged public var id: UUID?
    
    // Identifier for the farmer being surveyed
    @NSManaged public var farmerId: String
    
    // The specific template or survey type identifier
    @NSManaged public var surveyId: String
    
    // Current synchronization state: "PENDING", "IN_PROGRESS", "SYNCED", or "FAILED"
    @NSManaged public var statusValue: String
    
    // Details regarding why a sync attempt may have failed
    @NSManaged public var failureReason: String?
    
    // Tracks the number of times a sync has been attempted
    @NSManaged public var retryCount: Int64
    
    // The timestamp when the survey was first initiated
    @NSManaged public var createdAt: Date
    
    // The timestamp when the survey was successfully uploaded to the server
    @NSManaged public var syncedAt: Date?
    
    // Total size of the survey data (including associated files) stored locally
    @NSManaged public var localStorageBytes: Int64
        
    // MARK: - Relationships
    
    // One-to-many relationship containing all the individual sections of the survey
    @NSManaged public var sections: NSSet?
    
    // One-to-many relationship containing all associated media or file attachments
    @NSManaged public var attachments: NSSet?
    
    // MARK: - Computed Properties for UI
    
    // Provides an ordered array of survey sections sorted by their repetition index
    public var sectionsList: [CDSurveySection] {
        let set = sections as? Set<CDSurveySection> ?? []
            
        return set.sorted { (section1: CDSurveySection, section2: CDSurveySection) -> Bool in
            // Ensures sections appear in the UI in the order they were filled or intended
            return section1.repetitionIndex < section2.repetitionIndex
        }
    }
        
    // Provides an ordered array of attachments sorted chronologically by creation date
    public var attachmentsList: [CDSurveyAttachment] {
        let set = attachments as? Set<CDSurveyAttachment> ?? []
            
        return set.sorted { (attachment1: CDSurveyAttachment, attachment2: CDSurveyAttachment) -> Bool in
            let date1 = attachment1.createdAt ?? Date.distantPast
            let date2 = attachment2.createdAt ?? Date.distantPast
            return date1 < date2
        }
    }
    
}

extension CDSurveyResponse {
    // Standard helper to generate a fetch request for the CDSurveyResponse entity
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDSurveyResponse> {
        return NSFetchRequest<CDSurveyResponse>(entityName: "CDSurveyResponse")
    }
}
