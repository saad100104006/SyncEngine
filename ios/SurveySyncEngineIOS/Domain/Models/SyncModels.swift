//
//  SyncResult.swift
//  SurveySyncEngineIOS
//

import Foundation

// MARK: - 1. Failed Item Helper
/// A lightweight container used to track a specific survey that failed to synchronize and the error encountered.
public struct FailedItem : Equatable {
    // The unique ID of the survey response that failed to upload
    public let responseId: String
    // The specific SyncError category that caused the failure
    public let error: SyncError
    
    public init(responseId: String, error: SyncError) {
        self.responseId = responseId
        self.error = error
    }
}

// MARK: - 2. Sync Result (Sealed Class Equivalent)
/// Represents the final outcome of a synchronization session, categorized by how the process concluded.
public enum SyncResult: Equatable {
    
    /// Indicates that the engine attempted to process every item in the current queue.
    /// Includes lists of IDs for those that succeeded and FailedItem objects for those that did not.
    case completed(succeeded: [String], failed: [FailedItem])
    
    /// Indicates the process was halted mid-queue (e.g., due to a sudden loss of internet or critical error).
    case earlyTermination(
        succeeded: [String],
        failedBeforeStop: [FailedItem],
        reason: SyncError, // The specific error that triggered the halt
        remainingCount: Int // The number of items left in the queue that were not attempted
    )
    
    /// Returned if a sync request is made while another synchronization session is already active.
    case alreadyRunning
    
    /// Returned when the sync engine finds no pending or failed surveys that require processing.
    case nothingToSync
    
    /// Indicates the sync was bypassed due to system policies (e.g., low battery or being on a metered connection).
    case skipped(reason: String)
    
    // MARK: - Convenience Properties
    /// Helper property to quickly determine if the session finished with any unsuccessful uploads.
    public var hasPartialFailure: Bool {
        switch self {
        case .completed(_, let failed):
            // True if the 'failed' list contains any items
            return !failed.isEmpty
        case .earlyTermination:
            // An early termination is always considered a partial failure as the queue wasn't finished
            return true
        default:
            return false
        }
    }
}

// MARK: - 3. Sync Progress (Flow Equivalent)
/// Defines the various stages of an active synchronization session, allowing the UI to show real-time progress.
public enum SyncProgress {
    // Emitted when the engine first starts, providing the total size of the queue
    case started(totalCount: Int)
    
    // Emitted when the engine begins the network request for a specific survey
    case itemUploading(responseId: String, index: Int, total: Int)
    
    // Emitted when a specific survey and its attachments are fully confirmed by the server
    case itemSucceeded(responseId: String, index: Int, total: Int)
    
    // Emitted when an individual survey fails, but the engine is continuing to the next item
    case itemFailed(responseId: String, error: SyncError, index: Int, total: Int)
    
    // The terminal state of the progress stream, containing the final SyncResult
    case finished(result: SyncResult)
}
