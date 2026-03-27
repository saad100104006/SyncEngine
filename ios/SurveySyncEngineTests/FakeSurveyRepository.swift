//
//  FakeSurveyRepository.swift
//  SurveySyncEngineIOS
//
// .
//

import Foundation
import Combine

/// FakeSurveyRepository — a pure in-memory repository designed for lightning-fast unit tests.
/// This implementation allows tests to run without a real Core Data database or file system.
/// It uses an NSRecursiveLock for thread safety, ensuring that fast-paced async tests
/// don't encounter race conditions.
public class FakeSurveyRepository: SurveyRepository {

    // Thread safety lock to handle concurrent access from multiple background Tasks
    private let lock = NSRecursiveLock()
    
    // Internal reactive state (Replicates Kotlin's MutableStateFlow)
    // The dictionary key is the SurveyResponse.id for O(1) lookups.
    private let responsesSubject = CurrentValueSubject<[String: SurveyResponse], Never>([:])
    
    // Inspection helper used to verify that the SyncEngine is logging the correct audit events
    public var loggedEvents: [(event: String, detail: String?)] = []

    public init() {}

    // MARK: - Synchronous Inspection Helpers
    // These methods allow your XCTest cases to inspect state without using 'await',
    // making the test code cleaner and more readable.

    /// Synchronously checks the current SyncStatus of a specific survey.
    public func statusOf(id: String) -> SyncStatus? {
        lock.withLock { responsesSubject.value[id]?.status }
    }

    /// Synchronously retrieves the current retry count for a survey.
    public func retryCountOf(id: String) -> Int? {
        lock.withLock { responsesSubject.value[id]?.retryCount }
    }

    /// Synchronously retrieves the recorded failure message for a survey.
    public func failureReasonOf(id: String) -> String? {
        lock.withLock { responsesSubject.value[id]?.failureReason }
    }

    /// Returns a snapshot of all survey responses currently in memory.
    public func allResponses() -> [SurveyResponse] {
        lock.withLock { Array(responsesSubject.value.values) }
    }

    // MARK: - Repository Protocol Implementation (Async)

    /// Saves a survey response to the in-memory dictionary and broadcasts the change to any observers.
    public func saveResponse(_ response: SurveyResponse) async throws {
        lock.withLock {
            var current = responsesSubject.value
            current[response.id] = response
            responsesSubject.send(current)
        }
    }

    /// Updates an existing survey's status to .inProgress.
    public func markInProgress(responseId: String) async throws {
        try update(id: responseId) { response in
            var r = response
            r.status = .inProgress
            return r
        }
    }

    /// Marks a survey as successfully synced, clearing any previous failure reasons.
    public func markSynced(responseId: String, syncedAt: Int64) async throws {
        try update(id: responseId) { response in
            var r = response
            r.status = .synced
            r.syncedAt = syncedAt
            r.failureReason = nil
            return r
        }
    }

    /// Records a failure status, updated reason, and the new retry count.
    public func markFailed(responseId: String, reason: String, retryCount: Int) async throws {
        try update(id: responseId) { response in
            var r = response
            r.status = .failed
            r.failureReason = reason
            r.retryCount = retryCount
            return r
        }
    }

    /// Marks a survey as "dead," meaning it won't be retried due to a terminal error.
    public func markDead(responseId: String, reason: String) async throws {
            try update(id: responseId) { response in
                var r = response
                r.status = .dead
                r.failureReason = reason
                return r
            }
        }

    /// Safety utility to move any surveys stuck in .inProgress back to .pending (e.g., after a simulated crash).
    public func resetStuckInProgress() async throws {
        lock.withLock {
            let updated = responsesSubject.value.mapValues { v in
                if v.status == .inProgress {
                    var r = v
                    r.status = .pending
                    return r
                }
                return v
            }
            responsesSubject.send(updated)
        }
    }

    // MARK: - Observation Flow

    /// Bridges the Combine CurrentValueSubject to a Swift Concurrency AsyncStream.
    /// Emits the full list of surveys sorted by creation date (newest first) whenever any survey changes.
    public func observeAllResponses() -> AsyncStream<[SurveyResponse]> {
        return AsyncStream { continuation in
            let cancellable = responsesSubject
                .map { Array($0.values).sorted(by: { $0.createdAt > $1.createdAt }) }
                .sink { continuation.yield($0) }
            
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    /// Provides an AsyncStream of surveys filtered by a specific SyncStatus (e.g., watching only 'Pending' items).
    public func observeByStatus(status: SyncStatus) -> AsyncStream<[SurveyResponse]> {
        return AsyncStream { continuation in
            let cancellable = responsesSubject
                .map { map in
                    map.values
                        .filter { $0.status == status }
                        .sorted(by: { $0.createdAt > $1.createdAt })
                }
                .sink { continuation.yield($0) }
            
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    // MARK: - Stats & Query Logic

    /// Returns a list of all surveys that need to be synchronized (status is .pending or .failed).
    /// Sorted oldest-first to ensure chronological processing.
    public func getPendingResponses() async throws -> [SurveyResponse] {
        lock.withLock {
            responsesSubject.value.values
                .filter { $0.status == .pending || $0.status == .failed }
                .sorted {
                    if $0.createdAt == $1.createdAt {
                        return $0.id < $1.id // Deterministic fallback for identical timestamps
                    }
                    return $0.createdAt < $1.createdAt
                }
        }
    }

    /// Retrieves a single survey from memory by its ID.
    public func getResponseById(id: String) async throws -> SurveyResponse? {
        lock.withLock { responsesSubject.value[id] }
    }

    /// Generates mock storage statistics based on the in-memory dictionary.
    public func getStorageStats() async throws -> StorageStats {
        lock.withLock {
            let responses = responsesSubject.value.values
            let totalAttachments = responses.reduce(0) { $0 + $1.attachments.count }
            
            return StorageStats(
                totalPendingBytes: responses.filter { $0.status != .synced }.reduce(0) { $0 + $1.localStorageBytes },
                totalSyncedBytes: responses.filter { $0.status == .synced }.reduce(0) { $0 + $1.localStorageBytes },
                availableDeviceBytes: 4 * 1024 * 1024 * 1024, // Simulated 4GB free space
                attachmentCount: totalAttachments
            )
        }
    }

    /// Logs a synchronization event into the public `loggedEvents` array for test assertion.
    public func logSyncEvent(sessionId: String, responseId: String?, event: String, detail: String?) async throws {
        lock.withLock {
            loggedEvents.append((event, detail))
        }
    }

    // MARK: - Private Logic

    /// Thread-safe internal helper to perform a transformation on a specific survey.
    private func update(id: String, transform: (SurveyResponse) -> SurveyResponse) throws {
        lock.withLock {
            var current = responsesSubject.value
            guard let existing = current[id] else { return }
            current[id] = transform(existing)
            responsesSubject.send(current)
        }
    }
    
    // MARK: - Protocol Stubs
    // These methods satisfy the SurveyRepository requirements but aren't utilized in basic engine tests.
    
    public func markAttachmentUploaded(attachmentId: String, serverUrl: String) async throws {}
    public func markAttachmentFailed(attachmentId: String) async throws {}
    public func getDiagnosticsSnapshot() async throws -> DiagnosticsSnapshot {
        return DiagnosticsSnapshot(pendingCount: 0, failedCount: 0, syncedCount: 0, oldestPendingAgeMs: nil, totalStorageBytes: 0, recentSyncErrors: [], deviceStorageAvailableBytes: 0)
    }
    public func pruneUploadedMedia(olderThanMs: Int64) async throws -> Int64 { return 0 }
    public func pruneSyncedResponses(olderThanMs: Int64) async throws -> Int { return 0 }
}

// MARK: - Lock Extension
extension NSLocking {
    /// A convenience wrapper to execute a closure within a lock/unlock cycle.
    func withLock<T>(_ block: () -> T) -> T {
        lock()
        defer { unlock() }
        return block()
    }
}
