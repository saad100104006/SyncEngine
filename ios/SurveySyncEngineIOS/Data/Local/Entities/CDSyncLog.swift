//
//  CDSyncLog.swift
//  SurveySyncEngineIOS
//
//

import Foundation
import CoreData

// Core Data entity used to track the history and status of synchronization events
@objc(CDSyncLog)
public class CDSyncLog: NSManagedObject {

    // Standard helper method to create a fetch request for retrieving sync logs
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDSyncLog> {
        return NSFetchRequest<CDSyncLog>(entityName: "CDSyncLog")
    }

    // Identifies the specific sync session (useful for grouping multiple logs from one sync run)
    @NSManaged public var sessionId: String
    
    // Optional reference to the specific Survey Response ID being processed
    @NSManaged public var responseId: String?
    
    // The type of event being logged (e.g., "SYNC_START", "UPLOAD_SUCCESS", "NETWORK_ERROR")
    @NSManaged public var event: String
    
    // Additional context or error messages related to the event
    @NSManaged public var detail: String?
    
    // The exact date and time the log entry was recorded
    @NSManaged public var timestamp: Date

}

// MARK: - Extension for Clean Helpers
extension CDSyncLog {
    /// Convenience initializer to streamline the creation of log entries within the Repository or Sync Engine
    convenience init(
        context: NSManagedObjectContext,
        sessionId: String,
        responseId: String?,
        event: String,
        detail: String?
    ) {
        // Locate the entity description within the provided managed object context
        let entity = NSEntityDescription.entity(forEntityName: "CDSyncLog", in: context)!
        
        // Initialize the object and insert it into the database context
        self.init(entity: entity, insertInto: context)
        
        // Map the passed parameters to the entity attributes
        self.sessionId = sessionId
        self.responseId = responseId
        self.event = event
        self.detail = detail
        
        // Automatically set the timestamp to the current moment of initialization
        self.timestamp = Date()
    }
}
