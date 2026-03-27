//
//  FakeRepositoryAdapter.swift
//  SurveySyncEngineIOS
//
// .
//

import Foundation

// ---------------------------------------------------------------------------
// FakeRepositoryAdapter
// ---------------------------------------------------------------------------
/// An adapter class that bridges the `FakeSurveyRepository` used in tests to the
/// formal `SurveyRepository` protocol. This allows the SyncEngine to interact with
/// mock data without knowing it is running in a test environment.
public class FakeRepositoryAdapter: SurveyRepository {
    // The underlying mock data source
    private let fake: FakeSurveyRepository

    /// Initializes the adapter with a specific fake repository instance.
    public init(fake: FakeSurveyRepository) {
        self.fake = fake
    }

    // MARK: - Write Operations

    /// Forwards the save request to the fake repository's in-memory storage.
    public func saveResponse(_ response: SurveyResponse) async throws {
        try await fake.saveResponse(response)
    }

    /// Forwards the status update to mark a survey as currently being processed.
    public func markInProgress(responseId: String) async throws {
        try await fake.markInProgress(responseId: responseId)
    }

    /// Forwards the completion update to the fake repository.
    public func markSynced(responseId: String, syncedAt: Int64) async throws {
        try await fake.markSynced(responseId: responseId, syncedAt: syncedAt)
    }

    /// Records a simulated failure and retry count in the fake repository.
    public func markFailed(responseId: String, reason: String, retryCount: Int) async throws {
        try await fake.markFailed(responseId: responseId, reason: reason, retryCount: retryCount)
    }

    /// Marks a response as permanently failed within the mock storage.
    public func markDead(responseId: String, reason: String) async throws {
        try await fake.markDead(responseId: responseId, reason: reason)
    }

    /// Resets any mock surveys stuck in a simulated "In Progress" state.
    public func resetStuckInProgress() async throws {
        try await fake.resetStuckInProgress()
    }

    /// Updates the mock status of a file attachment.
    public func markAttachmentUploaded(attachmentId: String, serverUrl: String) async throws {
        try await fake.markAttachmentUploaded(attachmentId: attachmentId, serverUrl: serverUrl)
    }

    /// Updates the mock status of a failed file attachment.
    public func markAttachmentFailed(attachmentId: String) async throws {
        try await fake.markAttachmentFailed(attachmentId: attachmentId)
    }

    // MARK: - Read Operations

    /// Retrieves all surveys currently marked as pending or failed in the mock source.
    public func getPendingResponses() async throws -> [SurveyResponse] {
        return try await fake.getPendingResponses()
    }

    /// Fetches a specific survey from the in-memory mock storage.
    public func getResponseById(id: String) async throws -> SurveyResponse? {
        return try await fake.getResponseById(id: id)
    }

    /// Provides a stream of mock data for testing UI observations.
    public func observeAllResponses() -> AsyncStream<[SurveyResponse]> {
        return fake.observeAllResponses()
    }

    /// Provides a filtered stream of mock data based on sync status.
    public func observeByStatus(status: SyncStatus) -> AsyncStream<[SurveyResponse]> {
        return fake.observeByStatus(status: status)
    }

    // MARK: - Storage Management

    /// Returns simulated storage metrics (e.g., used bytes, available space).
    public func getStorageStats() async throws -> StorageStats {
        return try await fake.getStorageStats()
    }

    /// Simulates the deletion of old media files and returns the bytes "freed".
    public func pruneUploadedMedia(olderThanMs: Int64) async throws -> Int64 {
        return try await fake.pruneUploadedMedia(olderThanMs: olderThanMs)
    }

    /// Simulates the removal of old synchronized database records.
    public func pruneSyncedResponses(olderThanMs: Int64) async throws -> Int {
        return try await fake.pruneSyncedResponses(olderThanMs: olderThanMs)
    }

    // MARK: - Diagnostics

    /// Generates a point-in-time health report based on the current mock data.
    public func getDiagnosticsSnapshot() async throws -> DiagnosticsSnapshot {
        return try await fake.getDiagnosticsSnapshot()
    }

    /// Logs a simulated sync event for audit trail verification in tests.
    public func logSyncEvent(sessionId: String, responseId: String?, event: String, detail: String?) async throws {
        try await fake.logSyncEvent(sessionId: sessionId, responseId: responseId, event: event, detail: detail)
    }
}
