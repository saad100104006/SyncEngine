//
//  SyncEngine.swift
//  SurveySyncEngineIOS
//

import Foundation
import Combine

// ---------------------------------------------------------------------------
// UploadOutcome — internal type that keeps success/failure explicit within
// the upload loop without resorting to optionals or thrown errors.
// ---------------------------------------------------------------------------
private enum UploadOutcome {
    case success
    case failure(SyncError)
}

/// A contract defining the synchronization engine's capabilities.
/// Adopters (like our SyncEngine actor) provide thread-safe implementations
/// of these requirements.
public protocol SyncEngineProtocol: Actor {
    func sync() async -> SyncResult
    var progressPublisher: AnyPublisher<SyncProgress, Never> { get }
}

// ---------------------------------------------------------------------------
// SyncEngine
//
// Declared as an `actor` — Swift's native concurrency primitive for protecting
// mutable state. This replaces the previous class + NSLock + isSyncInProgress
// approach with a guarantee enforced by the Swift runtime.
//
// Why actor instead of class + NSLock:
//   The actor runtime serialises access to all methods and stored properties.
//   `isRunning` can be read and written without a lock because the compiler
//   prevents concurrent access at compile time, not at runtime.
//
//   With the old class approach:
//     • NSLock is a blocking, synchronous primitive in an async context.
//     • There was a window between releasing the lock and entering runSync()
//       where the flag was set but the lock was not held — theoretically unsafe.
//     • Passing NSLock as a constructor parameter to satisfy tests was a
//       workaround that exposed an implementation detail.
//
//   With actor:
//     • No lock, no flag management, no constructor parameter.
//     • Scenario 4 (concurrent sync prevention) is provably correct — the
//       compiler rejects any code that could violate isolation.
//
// Progress reporting:
//   `progressPublisher` is a Combine AnyPublisher exposed as a `nonisolated`
//   computed property. `nonisolated` means callers can subscribe from any
//   context without hopping onto the actor's executor. The underlying
//   PassthroughSubject is also `nonisolated` because it is a let constant
//   (reference type, internally thread-safe via Combine's own locking).
//
// Scenarios handled:
//   1. Offline storage  — delegates to repository; engine reads pending queue
//   2. Partial failure  — per-item status via markFailed / markDead
//   3. Network degradation — NetworkErrorClassifier triggers early termination
//   4. Concurrent sync  — actor isolation replaces NSLock + Bool flag
//   5. Error mapping    — Throwable.toSyncError() normalises all failure types
//
// Bonus:
//   • Progress reporting via Combine AnyPublisher<SyncProgress, Never>
//   • Device-aware policy via DevicePolicyEvaluator
//   • Diagnostic logging via SurveyRepository.logSyncEvent()
// ---------------------------------------------------------------------------
public actor SyncEngine: SyncEngineProtocol {

    // ------------------------------------------------------------------
    // Dependencies — all protocols, no concrete types
    // ------------------------------------------------------------------
    private let repository: SurveyRepository
    private let apiService: SurveyApiService
    private let devicePolicy: DevicePolicyEvaluator
    private let errorClassifier: NetworkErrorClassifier

    // ------------------------------------------------------------------
    // Concurrency guard
    //
    // Protected by the actor — no lock needed.
    // The runtime ensures only one caller can read or write `isRunning`
    // at a time, making the check-and-set atomic by construction.
    // ------------------------------------------------------------------
    private var isRunning = false

    // ------------------------------------------------------------------
    // Progress stream
    //
    // `nonisolated` so callers can access `progressPublisher` without
    // awaiting the actor. PassthroughSubject is a class (reference type)
    // and is thread-safe internally via Combine's lock, so this is safe.
    // ------------------------------------------------------------------
    private let progressSubject = PassthroughSubject<SyncProgress, Never>()

    /// Subscribe to this publisher to receive real-time sync progress events.
    /// Safe to access from any context — does not require `await`.
    public nonisolated var progressPublisher: AnyPublisher<SyncProgress, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    // ------------------------------------------------------------------
    // Retention windows
    // ------------------------------------------------------------------

    /// Uploaded media files (photos) are pruned after 3 days.
    /// Keeps storage bounded on 16–32 GB field devices.
    private static let mediaRetentionMs:  Int64 = 3  * 24 * 60 * 60 * 1000

    /// Synced response records (metadata only) are pruned after 30 days.
    /// Records are small — keeping them longer aids diagnostics.
    private static let recordRetentionMs: Int64 = 30 * 24 * 60 * 60 * 1000

    // ------------------------------------------------------------------
    // Init
    //
    // No `mutex` parameter — actor isolation makes it unnecessary.
    // Existing call sites in TestSyncEngineFactory just remove that argument.
    // ------------------------------------------------------------------

    /// Creates a SyncEngine with the given dependencies.
    /// - Parameters:
    ///   - repository: Local persistence layer (domain protocol).
    ///   - apiService: Remote upload service (domain protocol).
    ///   - devicePolicy: Evaluates battery / storage / network before syncing.
    ///   - errorClassifier: Tracks consecutive network failures for early termination.
    public init(
        repository: SurveyRepository,
        apiService: SurveyApiService,
        devicePolicy: DevicePolicyEvaluator = FakeDevicePolicyEvaluator(),
        errorClassifier: NetworkErrorClassifier = NetworkErrorClassifier()
    ) {
        self.repository = repository
        self.apiService = apiService
        self.devicePolicy = devicePolicy
        self.errorClassifier = errorClassifier
    }

    // MARK: - Public API

    /// Attempts to sync all pending responses.
    ///
    /// Returns immediately with `.alreadyRunning` if a sync session is already
    /// in flight — the caller does not need to debounce.
    ///
    /// The actor runtime guarantees that `isRunning` is read and written
    /// atomically — no lock required.
    public func sync() async -> SyncResult {
        // Scenario 4: actor isolation makes this check-and-set atomic.
        // No two callers can execute this block concurrently.
        guard !isRunning else { return .alreadyRunning }
        isRunning = true
        defer { isRunning = false }

        // Device policy check — battery, storage, network type
        let policy = devicePolicy.evaluate()
        guard policy.shouldSync else {
            return .skipped(reason: policy.skipReason ?? "Policy blocked sync")
        }

        return await runSync(sessionId: UUID().uuidString, policy: policy)
    }

    // MARK: - Internal Logic

    /// Main upload loop — iterates the pending queue and handles each response.
    private func runSync(sessionId: String, policy: SyncPolicy) async -> SyncResult {

        // Scenario 1 — storage growth management.
        // Pruning runs before loading the queue so freed space is available
        // immediately. Errors are swallowed — a pruning failure must never
        // block a sync session.
        await pruneStaleData(sessionId: sessionId)

        // Re-evaluate policy after pruning in case storage state changed
        let currentPolicy = devicePolicy.evaluate()
        guard currentPolicy.shouldSync else {
            await log(sessionId, event: "SKIPPED", detail: currentPolicy.skipReason)
            return .skipped(reason: currentPolicy.skipReason ?? "Policy blocked sync")
        }

        guard let pending = try? await repository.getPendingResponses(),
              !pending.isEmpty else {
            return .nothingToSync
        }

        await log(sessionId, event: "STARTED",
                  detail: "pending=\(pending.count), network=\(currentPolicy.networkType)")
        emit(.started(totalCount: pending.count))

        var succeeded: [String] = []
        var failed: [FailedItem] = []
        errorClassifier.reset()

        var bytesUploadedThisSession: Int64 = 0

        for (index, response) in pending.enumerated() {

            // Bonus: metered network byte cap — stop early rather than
            // burning the agent's data quota on a large queue
            if let maxBytes = currentPolicy.maxBytesPerSession,
               bytesUploadedThisSession >= maxBytes {
                let remaining = pending.count - index
                await log(sessionId, event: "BYTE_CAP_REACHED",
                          detail: "remaining=\(remaining)")
                let termination = SyncResult.earlyTermination(
                    succeeded: succeeded,
                    failedBeforeStop: failed,
                    reason: .networkUnavailable(URLError(.backgroundSessionWasDisconnected)),
                    remainingCount: remaining
                )
                emit(.finished(result: termination))
                return termination
            }

            // Bonus: low-battery throttle — add a delay between items to
            // reduce CPU wake time and extend field device battery life
            if currentPolicy.itemDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(currentPolicy.itemDelay) * 1_000_000)
            }

            emit(.itemUploading(responseId: response.id, index: index, total: pending.count))
            try? await repository.markInProgress(responseId: response.id)

            let outcome = await uploadResponse(response: response)

            switch outcome {
            case .success:
                try? await repository.markSynced(
                    responseId: response.id,
                    syncedAt: Int64(Date().timeIntervalSince1970 * 1000)
                )
                errorClassifier.recordSuccess()
                succeeded.append(response.id)
                bytesUploadedThisSession += response.localStorageBytes
                await log(sessionId, responseId: response.id, event: "ITEM_SYNCED")
                emit(.itemSucceeded(responseId: response.id, index: index, total: pending.count))

            case .failure(let error):
                // Scenario 5 — retryable vs permanent failure distinction:
                //   isRetryable() = true  → network/5xx → markFailed → retried next sync
                //   isRetryable() = false → 4xx bad payload → markDead → never retried
                if error.isRetryable() {
                    try? await repository.markFailed(
                        responseId: response.id,
                        reason: error.userFacingMessage(),
                        retryCount: response.retryCount + 1
                    )
                } else {
                    try? await repository.markDead(
                        responseId: response.id,
                        reason: error.userFacingMessage()
                    )
                }

                errorClassifier.recordFailure(error)
                failed.append(FailedItem(responseId: response.id, error: error))
                await log(sessionId, responseId: response.id,
                          event: "ITEM_FAILED", detail: error.userFacingMessage())
                emit(.itemFailed(responseId: response.id, error: error,
                                 index: index, total: pending.count))

                // Scenario 3 — abort early on consecutive network failures
                // to conserve battery and stop wasting the agent's data quota
                if errorClassifier.shouldAbort() {
                    let remaining = pending.count - index - 1
                    await log(sessionId, event: "EARLY_STOP",
                              detail: "consecutive_failures=\(errorClassifier.consecutiveCount()), remaining=\(remaining)")
                    let termination = SyncResult.earlyTermination(
                        succeeded: succeeded,
                        failedBeforeStop: failed,
                        reason: error,
                        remainingCount: remaining
                    )
                    emit(.finished(result: termination))
                    return termination
                }
            }
        }

        let completed = SyncResult.completed(succeeded: succeeded, failed: failed)
        await log(sessionId, event: "COMPLETED",
                  detail: "succeeded=\(succeeded.count), failed=\(failed.count)")
        emit(.finished(result: completed))
        return completed
    }

    // MARK: - Storage Management

    /// Deletes stale media files and old synced records before each session.
    /// Uses separate retention windows: photos (3 days) vs records (30 days).
    /// Failure is caught and logged — pruning must never abort a sync session.
    private func pruneStaleData(sessionId: String) async {
        do {
            let mediaFreed = try await repository.pruneUploadedMedia(
                olderThanMs: Self.mediaRetentionMs
            )
            let recordsDeleted = try await repository.pruneSyncedResponses(
                olderThanMs: Self.recordRetentionMs
            )
            if mediaFreed > 0 || recordsDeleted > 0 {
                await log(sessionId, event: "PRUNED",
                          detail: "media_freed_bytes=\(mediaFreed), records_deleted=\(recordsDeleted)")
            }
        } catch {
            await log(sessionId, event: "PRUNE_ERROR", detail: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// Wraps the network call and maps any thrown error to the SyncError hierarchy.
    private func uploadResponse(response: SurveyResponse) async -> UploadOutcome {
        do {
            _ = try await apiService.uploadSurveyResponse(response: response)
            return .success
        } catch {
            return .failure(error.toSyncError())
        }
    }

    private func log(
        _ sessionId: String,
        responseId: String? = nil,
        event: String,
        detail: String? = nil
    ) async {
        try? await repository.logSyncEvent(
            sessionId: sessionId,
            responseId: responseId,
            event: event,
            detail: detail
        )
    }

    /// Sends a progress event to all current subscribers.
    /// `progressSubject` is a class-based reference type with internal
    /// thread safety, so calling `send` from inside the actor is safe.
    private func emit(_ progress: SyncProgress) {
        progressSubject.send(progress)
    }
}
