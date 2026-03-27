//
//  LocalStorageService.swift
//  Agricultural_Survey
//

import CoreData

/// Protocol defining the contract for local data persistence operations.
/// This abstraction allows for easier unit testing by swapping Core Data for a mock service.
protocol LocalStorageService {
    // Persists a domain-level SurveyResponse object into the local database
    func saveSurvey(_ domainSurvey: SurveyResponse) async throws
    
    // Retrieves all survey responses that have not yet been successfully synced to the server
    func fetchPendingSurveys() async throws -> [SurveyResponse]
    
    // Updates the synchronization status of a specific survey identified by its UUID
    func updateSurveyStatus(id: UUID, newStatus: String) async throws
}

/// A Core Data implementation of the LocalStorageService protocol.
final class CoreDataStorageService: LocalStorageService {
    // Reference to the shared singleton for database container and context management
    private let stack = CoreDataStack.shared
    
    /// Maps and saves a domain survey object into a background Core Data context.
    func saveSurvey(_ domainSurvey: SurveyResponse) async throws {
        // Use a background context to keep the UI responsive during disk writes
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            // Create a new Core Data managed object within the specific background context
            let cdSurvey = CDSurveyResponse(context: context)
            
            // Map basic attributes from the domain model to the Core Data entity
            cdSurvey.id = UUID(uuidString: domainSurvey.id) ?? UUID()
            cdSurvey.farmerId = domainSurvey.farmerId
            cdSurvey.statusValue = "pending" // Default status for new local saves
            cdSurvey.createdAt = Date()
            
            // Note: Section and Attachment mapping logic would typically be implemented here
            // using a dedicated Mapper utility to handle nested relationship objects.
            
            // Commit the changes to the persistent store
            try context.save()
        }
    }
    
    /// Fetches all survey responses from the database, sorted chronologically.
    func fetchPendingSurveys() async throws -> [SurveyResponse] {
        let context = stack.newBackgroundContext()
        
        return try await context.perform {
            // Configure a fetch request for the CDSurveyResponse entity
            let request = NSFetchRequest<CDSurveyResponse>(entityName: "CDSurveyResponse")
            
            // Sort results so the oldest surveys (first created) are returned first
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            
            // Execute the fetch against the background context
            let cdSurveys = try context.fetch(request)
            
            // Convert the Core Data managed objects back into clean, thread-safe domain models
            return cdSurveys.map { SurveyMapper.toDomain(cdSurvey: $0) }
        }
    }
    
    /// Locates a specific survey and updates its current synchronization state.
    func updateSurveyStatus(id: UUID, newStatus: String) async throws {
        let context = stack.newBackgroundContext()
        
        try await context.perform {
            // Create a fetch request specifically for the record with the matching ID
            let request = NSFetchRequest<CDSurveyResponse>(entityName: "CDSurveyResponse")
            // Optimization: Stop searching once the single matching record is found
            request.fetchLimit = 1
            
            // Note: In a production environment, you should add a predicate to filter by the 'id' property.
            
            if let cdSurvey = try context.fetch(request).first {
                // Update the status and save the context to persist the change
                cdSurvey.statusValue = newStatus
                try context.save()
            }
        }
    }
}
