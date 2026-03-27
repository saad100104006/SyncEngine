//
//  SurveyRepositoryImpl.swift
//  SurveySyncEngineIOS
//
//

import Foundation
import CoreData

/// Concrete implementation of the SurveyRepository, handling data persistence,
/// observation, and storage maintenance using Core Data.
public class SurveyRepositoryImpl: SurveyRepository {
    
    private let context: NSManagedObjectContext
    
    // Closure that provides the current amount of free disk space on the device
    private let availableStorageProvider: () -> Int64
    
    public init(
        context: NSManagedObjectContext,
        availableStorageProvider: @escaping () -> Int64 = {
            // Native iOS way to check available device storage via resource values
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try? fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values?.volumeAvailableCapacityForImportantUsage ?? 0
        }
    ) {
        self.context = context
        self.availableStorageProvider = availableStorageProvider
    }
    
    // MARK: - Write Operations
    
    /// Maps a domain SurveyResponse to Core Data and persists it to the database.
    public func saveResponse(_ response: SurveyResponse) async throws {
        try await context.perform {
            // 1. Map the domain object to Core Data managed objects
            let _ = SurveyMapper.toCoreData(survey: response, context: self.context)
            
            // 2. Persist the new entity and its relationships to the local store
            if self.context.hasChanges {
                try self.context.save()
            } else {
                print("DEBUG: Context had no changes to save!")
            }
        }
    }

    /// Updates a survey's status to indicate it is currently being processed by the sync engine.
    public func markInProgress(responseId: String) async throws {
        try await updateStatus(id: responseId, status: .inProgress)
    }
    
    /// Marks a survey as successfully synchronized with the remote server.
    public func markSynced(responseId: String, syncedAt: Int64) async throws {
        try await context.perform {
            if let cdResponse = try self.fetchCDResponse(by: responseId) {
                cdResponse.statusValue = SyncStatus.synced.rawValue
                // Convert incoming millisecond timestamp to a Foundation Date
                cdResponse.syncedAt = Date(timeIntervalSince1970: TimeInterval(syncedAt) / 1000.0)
                try self.context.save()
            }
        }
    }
    
    /// Records a failed sync attempt, updating the reason and incrementing the retry counter.
    public func markFailed(responseId: String, reason: String, retryCount: Int) async throws {
        try await context.perform {
            if let cdResponse = try self.fetchCDResponse(by: responseId) {
                cdResponse.statusValue = SyncStatus.failed.rawValue
                cdResponse.failureReason = reason
                cdResponse.retryCount = Int64(retryCount)
                try self.context.save()
            }
        }
    }
    
    /// Marks a response as 'dead' when it has exceeded the maximum retry limit and requires manual intervention.
    public func markDead(responseId: String, reason: String) async throws {
            try await context.perform {
                if let cdResponse = try self.fetchCDResponse(by: responseId) {
                    cdResponse.statusValue = SyncStatus.dead.rawValue
                    cdResponse.failureReason = reason
                    try self.context.save()
                }
            }
        }
    
    /// Recovery method to reset any surveys left in the "InProgress" state (e.g., after an app crash).
    public func resetStuckInProgress() async throws {
        try await self.context.perform {
            let request = NSFetchRequest<CDSurveyResponse>(entityName: "CDSurveyResponse")
            request.predicate = NSPredicate(format: "statusValue == %@", SyncStatus.inProgress.rawValue)
            
            let stuckResponses = try self.context.fetch(request)
                
            for response in stuckResponses {
                response.statusValue = SyncStatus.pending.rawValue
            }
            
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }
    
    /// Updates an attachment's status to 'Uploaded' and stores the returned server URL.
    public func markAttachmentUploaded(attachmentId: String, serverUrl: String) async throws {
        try await context.perform {
            if let cdAttachment = try self.fetchCDAttachment(by: attachmentId) {
                cdAttachment.uploadStatusValue = UploadStatus.uploaded.rawValue
                cdAttachment.serverUrl = serverUrl
                try self.context.save()
            }
        }
    }
    
    /// Marks an attachment as failed if the file upload was unsuccessful.
    public func markAttachmentFailed(attachmentId: String) async throws {
        try await context.perform {
            if let cdAttachment = try self.fetchCDAttachment(by: attachmentId) {
                cdAttachment.uploadStatusValue = UploadStatus.failed.rawValue
                try self.context.save()
            }
        }
    }
    
    // MARK: - Read Operations
    
    /// Retrieves all surveys that are currently awaiting synchronization or previously failed.
    public func getPendingResponses() async throws -> [SurveyResponse] {
        try await context.perform {
            let request: NSFetchRequest<CDSurveyResponse> = CDSurveyResponse.fetchRequest()
            
            // Includes both new pending items and those that need a retry
            request.predicate = NSPredicate(
                format: "statusValue == %@ OR statusValue == %@",
                SyncStatus.pending.rawValue,
                SyncStatus.failed.rawValue
            )
            
            let cdResponses = try self.context.fetch(request)
            return cdResponses.map { SurveyMapper.toDomain(cdSurvey: $0) }
        }
    }
    
    /// Fetches a single domain-level survey response by its ID.
    public func getResponseById(id: String) async throws -> SurveyResponse? {
        try await context.perform {
            guard let cdResponse = try self.fetchCDResponse(by: id) else { return nil }
            return SurveyMapper.toDomain(cdSurvey: cdResponse)
        }
    }
    
    /// Returns an asynchronous stream that emits the full list of responses whenever the database changes.
    public func observeAllResponses() -> AsyncStream<[SurveyResponse]> {
        createObservationStream(predicate: nil)
    }
    
    /// Returns an asynchronous stream filtered by a specific synchronization status.
    public func observeByStatus(status: SyncStatus) -> AsyncStream<[SurveyResponse]> {
        createObservationStream(predicate: NSPredicate(format: "statusValue == %@", status.rawValue))
    }
    
    // MARK: - Storage Management
    
    /// Calculates current database and device storage usage metrics.
    public func getStorageStats() async throws -> StorageStats {
        try await context.perform {
            let pendingBytes: Int64 = 0 // Implementation note: sum logic goes here
            let syncedBytes: Int64 = 0
            let totalAttachments = try self.context.count(for: CDSurveyAttachment.fetchRequest())
            
            return StorageStats(
                totalPendingBytes: pendingBytes,
                totalSyncedBytes: syncedBytes,
                availableDeviceBytes: self.availableStorageProvider(),
                attachmentCount: totalAttachments
            )
        }
    }
    
    /// Deletes local files and database records for media that has already been uploaded and is older than the threshold.
    public func pruneUploadedMedia(olderThanMs: Int64) async throws -> Int64 {
        try await context.perform {
            let cutoffDate = Date(timeIntervalSince1970: TimeInterval(Date().timeIntervalSince1970 * 1000 - Double(olderThanMs)) / 1000.0)
            
            let request = NSFetchRequest<CDSurveyAttachment>(entityName: "CDSurveyAttachment")
            request.predicate = NSPredicate(format: "uploadStatusValue == %@ AND createdAt < %@", UploadStatus.uploaded.rawValue, cutoffDate as NSDate)
            
            let oldAttachments = try self.context.fetch(request)
            var freedBytes: Int64 = 0
            
            for attachment in oldAttachments {
                let fileURL = URL(fileURLWithPath: attachment.localFilePath)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    do {
                        let attr = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                        freedBytes += (attr[.size] as? Int64) ?? 0
                        try FileManager.default.removeItem(at: fileURL)
                    } catch {
                        print("Failed to delete file: \(error)")
                    }
                }
                self.context.delete(attachment)
            }
            
            if self.context.hasChanges { try self.context.save() }
            return freedBytes
        }
    }
    
    /// Deletes database records for surveys already synchronized that exceed the age threshold.
    public func pruneSyncedResponses(olderThanMs: Int64) async throws -> Int {
        try await context.perform {
            let cutoffDate = Date(timeIntervalSince1970: TimeInterval(Date().timeIntervalSince1970 * 1000 - Double(olderThanMs)) / 1000.0)
            
            let request: NSFetchRequest<CDSurveyResponse> = CDSurveyResponse.fetchRequest()
            request.predicate = NSPredicate(format: "statusValue == %@ AND createdAt < %@", SyncStatus.synced.rawValue, cutoffDate as NSDate)
            
            let oldResponses = try self.context.fetch(request)
            let count = oldResponses.count
            
            for response in oldResponses {
                self.context.delete(response)
            }
            
            if self.context.hasChanges { try self.context.save() }
            return count
        }
    }
    
    // MARK: - Diagnostics & Logging

    /// Inserts a new synchronization log entry into the database.
    public func logSyncEvent(sessionId: String, responseId: String?, event: String, detail: String?) async throws {
        try await self.context.perform {
            let log = CDSyncLog(context: self.context)
            log.sessionId = sessionId
            log.responseId = responseId
            log.event = event
            log.detail = detail
            log.timestamp = Date()
            
            if self.context.hasChanges {
                try self.context.save()
            }
        }
    }
    
    // MARK: - Private Helpers
    
    /// Helper to find a CDSurveyResponse by ID.
    private func fetchCDResponse(by id: String) throws -> CDSurveyResponse? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let request: NSFetchRequest<CDSurveyResponse> = CDSurveyResponse.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    /// Helper to find a CDSurveyAttachment by ID.
    private func fetchCDAttachment(by id: String) throws -> CDSurveyAttachment? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let request: NSFetchRequest<CDSurveyAttachment> = CDSurveyAttachment.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    /// Internal status updater used across various public markX methods.
    private func updateStatus(id: String, status: SyncStatus) async throws {
        try await context.perform {
            if let cdResponse = try self.fetchCDResponse(by: id) {
                cdResponse.statusValue = status.rawValue
                try self.context.save()
            }
        }
    }
    
    /// Reactive stream helper that yields the result of a fetch request and re-runs on context changes.
    private func createObservationStream(predicate: NSPredicate?) -> AsyncStream<[SurveyResponse]> {
        AsyncStream { continuation in
            let request: NSFetchRequest<CDSurveyResponse> = CDSurveyResponse.fetchRequest()
            request.predicate = predicate
            
            // 1. Initial data push
            context.perform {
                let initial = (try? self.context.fetch(request)) ?? []
                continuation.yield(initial.map { SurveyMapper.toDomain(cdSurvey: $0) })
            }
            
            // 2. Observer for context changes to trigger subsequent pushes
            let observer = NotificationCenter.default.addObserver(
                forName: .NSManagedObjectContextObjectsDidChange,
                object: context,
                queue: nil
            ) { _ in
                self.context.perform {
                    let updated = (try? self.context.fetch(request)) ?? []
                    continuation.yield(updated.map { SurveyMapper.toDomain(cdSurvey: $0) })
                }
            }
            
            // 3. Cleanup logic
            continuation.onTermination = { @Sendable _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
    
    /// Provides a comprehensive view of the current system state for debugging and monitoring.
    public func getDiagnosticsSnapshot() async throws -> DiagnosticsSnapshot {
        try await context.perform {
            // 1. Collect counts per status
            let pendingCount = try self.countByStatus(.pending)
            let failedCount = try self.countByStatus(.failed)
            let syncedCount = try self.countByStatus(.synced)
            
            // 2. Aggregate attachment sizes
            let attachRequest: NSFetchRequest<CDSurveyAttachment> = CDSurveyAttachment.fetchRequest()
            let allAttachments = try self.context.fetch(attachRequest)
            let totalBytes = allAttachments.reduce(0) { $0 + $1.sizeBytes }
            
            // 3. Find age of the oldest pending response
            let oldestRequest: NSFetchRequest<CDSurveyResponse> = CDSurveyResponse.fetchRequest()
            oldestRequest.predicate = NSPredicate(format: "statusValue == %@", SyncStatus.pending.rawValue)
            oldestRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            oldestRequest.fetchLimit = 1
            
            var oldestAge: Int64? = nil
            if let oldest = try self.context.fetch(oldestRequest).first {
                let ageSeconds = Date().timeIntervalSince(oldest.createdAt)
                oldestAge = Int64(ageSeconds * 1000)
            }
            
            return DiagnosticsSnapshot(
                pendingCount: pendingCount,
                failedCount: failedCount,
                syncedCount: syncedCount,
                oldestPendingAgeMs: oldestAge,
                totalStorageBytes: totalBytes,
                recentSyncErrors: [],
                deviceStorageAvailableBytes: self.availableStorageProvider()
            )
        }
    }

    /// Internal counter for surveys by status type.
    private func countByStatus(_ status: SyncStatus) throws -> Int {
        let request: NSFetchRequest<CDSurveyResponse> = CDSurveyResponse.fetchRequest()
        request.predicate = NSPredicate(format: "statusValue == %@", status.rawValue)
        return try context.count(for: request)
    }
}
