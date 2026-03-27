//
//  SyncWorker.swift
//  SurveySyncEngineIOS
//
// .
//

import Foundation

/// Defines the outcome of a background worker task, mimicking Android's WorkManager API.
/// This allows the system to decide whether to reschedule, mark as finished, or handle a failure.
enum WorkerResult: Equatable {
    // The task completed successfully, optionally returning metadata about the run.
    case success(outputData: [String: Any])
    
    // The task failed due to a transient issue (like network loss) and should be retried later.
    case retry
    
    // The task failed due to a non-recoverable error.
    case failure

    /// Implementation of Equatable to allow for result comparison in unit tests.
    static func == (lhs: WorkerResult, rhs: WorkerResult) -> Bool {
        switch (lhs, rhs) {
        case (.retry, .retry): return true
        case (.failure, .failure): return true
        case (.success(let l), .success(let r)):
            // Simple comparison based on the result type string for testing purposes.
            return (l["resultType"] as? String) == (r["resultType"] as? String)
        default: return false
        }
    }
}

/// A wrapper class that adapts the SyncEngine's output into a format suitable for background task schedulers.
class SyncWorker {
    // Keys used for dictionary-based output data.
    static let KEY_RESULT_TYPE = "resultType"
    static let KEY_SUCCEEDED_COUNT = "succeededCount"
    static let KEY_FAILED_COUNT = "failedCount"

    private var syncEngine: SyncEngine

    /// Initializes the worker with a reference to the main SyncEngine.
    init(engine: SyncEngine) {
        self.syncEngine = engine
    }

    /// Performs the synchronization work and maps the complex SyncResult to a simplified WorkerResult.
    /// This is typically called from a BackgroundTasks handle or a recurring timer.
    func doWork() async -> WorkerResult {
        // Execute the main engine synchronization loop.
        let result = await syncEngine.sync()
        
        switch result {
        case .completed(let succeeded, let failed):
            // The engine finished the queue; return counts for diagnostics.
            let data: [String: Any] = [
                SyncWorker.KEY_RESULT_TYPE: "COMPLETED",
                SyncWorker.KEY_SUCCEEDED_COUNT: succeeded.count,
                SyncWorker.KEY_FAILED_COUNT: failed.count
            ]
            return .success(outputData: data)
            
        case .earlyTermination:
            // The network likely died mid-sync; tell the system to try again when conditions are better.
            return .retry
            
        case .nothingToSync:
            // No work was found; report success so the system doesn't immediately reschedule.
            return .success(outputData: [SyncWorker.KEY_RESULT_TYPE: "NOTHING_TO_SYNC"])
            
        case .alreadyRunning:
            // A sync is already in progress; report success to avoid redundant queuing.
            return .success(outputData: [SyncWorker.KEY_RESULT_TYPE: "ALREADY_RUNNING"])
            
        case .skipped(_):
            // Hardware policies (battery/storage) blocked the run; mark as successful non-event.
            return .success(outputData: [SyncWorker.KEY_RESULT_TYPE: "SKIPPED"])
            
        default:
            // Fallback for unrecognized terminal states.
            return .failure
        }
    }
}
