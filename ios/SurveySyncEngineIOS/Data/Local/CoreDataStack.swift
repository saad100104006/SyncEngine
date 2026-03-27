//
//  CoreDataStack.swift
//  Agricultural_Survey
//
//

import CoreData

/// A singleton class responsible for initializing and managing the Core Data stack.
final class CoreDataStack {
    // Shared instance for app-wide access to the database
    static let shared = CoreDataStack()
    
    // The container that encapsulates the Core Data stack (Model, Context, and Store Coordinator)
    let persistentContainer: NSPersistentContainer
    
    /// Initializes the stack, optionally in-memory for unit testing purposes.
    init(inMemory: Bool = false) {
        let modelName = "AgricSurvey"
        
        // 1. Create a helper to find the compiled data model (.momd) across all potential locations
        let model: NSManagedObjectModel = {
            // Attempt to find the model in the bundle where CoreDataStack is defined
            if let url = Bundle(for: CoreDataStack.self).url(forResource: modelName, withExtension: "momd"),
               let model = NSManagedObjectModel(contentsOf: url) {
                return model
            }
            
            // Attempt to find the model in the Main bundle (typical for app runs)
            if let url = Bundle.main.url(forResource: modelName, withExtension: "momd"),
               let model = NSManagedObjectModel(contentsOf: url) {
                return model
            }
            
            // CRITICAL FOR COMMAND LINE TESTS: Iterate through all loaded bundles to locate the model
            for bundle in Bundle.allBundles {
                if let url = bundle.url(forResource: modelName, withExtension: "momd"),
                   let model = NSManagedObjectModel(contentsOf: url) {
                    return model
                }
            }
            
            // Crash if the model cannot be found, as the app cannot function without its database schema
            fatalError("❌ Error: Could not find \(modelName).momd in any loaded bundle. Check Target Membership.")
        }()

        // 2. Initialize the container with the located managed object model
        persistentContainer = NSPersistentContainer(name: modelName, managedObjectModel: model)
        
        // Configure the persistent store description for migrations and testing
        if let description = persistentContainer.persistentStoreDescriptions.first {
            // Enable lightweight migration to automatically handle small schema changes
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            
            // Redirect storage to /dev/null if inMemory is true (useful for Unit Tests to avoid disk I/O)
            if inMemory {
                description.url = URL(fileURLWithPath: "/dev/null")
            }
        }

        // Load the actual database file from disk
        persistentContainer.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        
        // Configure the main view context for automatic UI updates and conflict resolution
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        // If a conflict occurs, the version currently in the object (the "Trump") wins over the database store
        persistentContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    /// Convenience property to access the main queue context for UI-related database work
    var mainContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    /// Creates a new private queue context for performing heavy background tasks without freezing the UI
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    /// Checks for unsaved changes in the main context and persists them to the disk
    func saveContext() {
        let context = persistentContainer.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nserror = error as NSError
                print("❌ Unresolved error saving context: \(nserror), \(nserror.userInfo)")
            }
        }
    }
}
