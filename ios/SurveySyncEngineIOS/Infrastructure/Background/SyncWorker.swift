//
//  SyncWorker.swift
//  SurveySyncEngineIOS
//
//

import Foundation
#if os(iOS)
import BackgroundTasks
#endif

/// A singleton manager that coordinates background synchronization across Apple platforms (iOS & macOS).
/// It handles task registration, scheduling, and execution within the system's background execution windows.
public final class SyncBackgroundTaskManager {
    
    public static let shared = SyncBackgroundTaskManager()
    
    // The unique identifier that must match the 'Permitted background task scheduler identifiers' in Info.plist
    private static let taskIdentifier = "com.surveysyncengine.background_sync"
    
    // Reference to the engine that performs the actual data transmission
    private var syncEngine: SyncEngine?
    
    private init() {}

    /// Injects the SyncEngine and registers the appropriate background listener based on the operating system.
    public func register(syncEngine: SyncEngine) {
        self.syncEngine = syncEngine
        
        #if os(iOS)
        // iOS: Register the handler for the background processing task.
        // This must be called before the app finishes launching (usually in AppDelegate/App struct).
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            // Cast to BGProcessingTask to access specialized background processing features
            self.handleIOSTask(task: task as! BGProcessingTask)
        }
        #elseif os(macOS)
        // macOS: Uses a recurring activity scheduler which is initiated during registration.
        self.scheduleMacActivity()
        #endif
    }

    /// Manually requests the system to schedule a future background sync attempt.
    public func scheduleNextSync() {
        #if os(iOS)
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        
        // Configuration: Ensure we have internet, but don't strictly require a charger
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        
        // Ask the system to wait at least 15 minutes before waking the app to sync
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("❌ iOS Background Submit Failed: \(error)")
        }
        #elseif os(macOS)
        // macOS background activity is self-managed once the activity object is scheduled.
        #endif
    }

    // MARK: - iOS Implementation
    #if os(iOS)
    /// Logic executed when iOS wakes the app to perform background work.
    private func handleIOSTask(task: BGProcessingTask) {
        // CRITICAL: iOS background tasks are one-off events.
        // We must schedule the "next" occurrence immediately to maintain a recurring loop.
        scheduleNextSync()
        
        // Handler called by the system if the background time budget is about to run out
        task.expirationHandler = {
            print("⏳ iOS Task Expired - Sync was interrupted by the system.")
        }
        
        // Execute the sync logic asynchronously
        Task {
            let result = await syncEngine?.sync()
            // Inform the system if the work was successful to help the scheduler optimize future wake-ups
            task.setTaskCompleted(success: result?.isSuccess ?? true)
        }
    }
    #endif

    // MARK: - macOS Implementation
    #if os(macOS)
    /// Sets up a recurring background activity for macOS.
    private func scheduleMacActivity() {
        let activity = NSBackgroundActivityScheduler(identifier: Self.taskIdentifier)
        activity.repeats = true
        activity.interval = 15 * 60 // Target interval: 15 minutes
        
        // Tolerance allows the system to drift the timing to align with other tasks for energy efficiency
        activity.tolerance = 5 * 60
        
        activity.schedule { completion in
            Task {
                _ = await self.syncEngine?.sync()
                // Notify the scheduler that this specific run is complete
                completion(.finished)
            }
        }
    }
    #endif
}

// MARK: - Result Mapping
extension SyncResult {
    /// Maps the complex SyncResult enum to a simple boolean for platform task completion handlers.
    var isSuccess: Bool {
        switch self {
        case .completed(_, let failed):
            // Successful if the queue was finished and no items failed
            return failed.isEmpty
        case .earlyTermination:
            // Always a failure as the entire queue wasn't processed
            return false
        default:
            // "Nothing to sync" or "Skipped" are considered successful non-events
            return true
        }
    }
}
