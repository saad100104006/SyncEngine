//
//  CDAttachment.swift
//  Agricultural_Survey
//

import Foundation
import CoreData

// Maps the Swift class to the 'CDSurveyAttachment' entity in the Core Data model
@objc(CDSurveyAttachment)
public class CDSurveyAttachment: NSManagedObject {
    
    // Unique identifier for the attachment instance
    @NSManaged public var id: UUID?
    
    // The file path on the local device; storing the path instead of raw Data keeps the database lightweight
    @NSManaged public var localFilePath: String
    
    // The format of the file (e.g., "image/jpeg", "application/pdf") for proper handling during upload or display
    @NSManaged public var mimeType: String
    
    // The size of the file in bytes, used for progress tracking or validation
    @NSManaged public var sizeBytes: Int64
    
    // Current state of the file sync (e.g., "PENDING", "UPLOADED", "FAILED")
    @NSManaged public var uploadStatusValue: String
    
    // The remote URL provided by the server once the upload is successfully completed
    @NSManaged public var serverUrl: String?
    
    // Timestamp indicating when the attachment record was first created
    @NSManaged public var createdAt: Date?
    
    // Inverse relationship linking this attachment to its parent survey response record
    @NSManaged public var survey: CDSurveyResponse?
}

extension CDSurveyAttachment {
    // Standard helper method to generate a fetch request specifically for CDSurveyAttachment entities
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDSurveyAttachment> {
        return NSFetchRequest<CDSurveyAttachment>(entityName: "CDSurveyAttachment")
    }
}
