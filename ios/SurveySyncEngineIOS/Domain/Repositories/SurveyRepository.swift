//
//  SurveyRepository.swift
//  SurveySyncEngineIOS
//
//

import Foundation

/// The abstraction layer for all data operations related to surveys.
/// This protocol defines how the Sync Engine and UI interact with the underlying database (Core Data).
public protocol SurveyRepository {
    
    // MARK: - Write Operations
    
    /// Persists a new or updated survey response to the local database.
    func saveResponse(_ response: SurveyResponse) async throws
    
    /// Updates the status of a survey to indicate it is currently in the sync queue.
    func markInProgress(responseId: String) async throws
    
    /// Marks a survey as successfully uploaded and stores the server's confirmation timestamp.
    func markSynced(responseId: String, syncedAt: Int64) async throws
    
    /// Records a failed sync attempt, including the error reason and updated retry count.
    func markFailed(responseId: String, reason: String, retryCount: Int) async throws
    
    /// Marks a survey as "dead" if it has permanently failed and should no longer be retried.
    func markDead(responseId: String, reason: String) async throws
    
    /// Recovery tool to reset any surveys stuck in the "InProgress" state (e.g., after an unexpected app termination).
    func resetStuckInProgress() async throws
    
    /// Updates the specific status and server-side URL for a successfully uploaded media file.
    func markAttachmentUploaded(attachmentId: String, serverUrl: String) async throws
    
    /// Marks a media attachment as failed if its specific upload process encountered an error.
    func markAttachmentFailed(attachmentId: String) async throws
    
    // MARK: - Read Operations
    
    /// Retrieves a list of all surveys that are either new or have previously failed and are eligible for sync.
    func getPendingResponses() async throws -> [SurveyResponse]
    
    /// Fetches a single survey response by its unique ID string.
    func getResponseById(id: String) async throws -> SurveyResponse?
    
    /// Returns a reactive stream (AsyncStream) that emits the full list of surveys whenever any database change occurs.
    func observeAllResponses() -> AsyncStream<[SurveyResponse]>
    
    /// Returns a reactive stream that emits updates only for surveys matching a specific SyncStatus.
    func observeByStatus(status: SyncStatus) -> AsyncStream<[SurveyResponse]>
    
    // MARK: - Storage Management
    
    /// Calculates the current byte-size of local data and available device capacity.
    func getStorageStats() async throws -> StorageStats
    
    /// Deletes local media files that have been successfully uploaded and exceed a certain age.
    /// - Returns: The total number of bytes freed from the device.
    func pruneUploadedMedia(olderThanMs: Int64) async throws -> Int64
    
    /// Removes database records for surveys already synchronized that exceed the age threshold.
    /// - Returns: The number of records deleted.
    func pruneSyncedResponses(olderThanMs: Int64) async throws -> Int
    
    // MARK: - Diagnostics & Logging
    
    /// Generates a summary of the current sync state, including counts of pending vs. synced items.
    func getDiagnosticsSnapshot() async throws -> DiagnosticsSnapshot
    
    /// Records a specific sync event (e.g., "SYNC_STARTED", "FILE_UPLOAD_ERROR") for debugging and audit trails.
    func logSyncEvent(sessionId: String, responseId: String?, event: String, detail: String?) async throws
}
