//
//  SyncEngine.swift
//  SurveySyncEngineIOS
//
//

import Foundation
import Combine

/// Internal outcome helper to keep success/failure branches explicit within the engine loop.
private enum UploadOutcome {
    case success
    case failure(SyncError)
}

/// The central orchestrator of the Survey Sync Engine.
/// It coordinates between the local database (Repository), the Network (ApiService),
/// and hardware constraints (DevicePolicy) to safely synchronize agricultural data.
public class SyncEngine {
    private let repository: SurveyRepository
    private let apiService: SurveyApiService
    private let devicePolicy: DevicePolicyEvaluator
    private let errorClassifier: NetworkErrorClassifier
    
    // Thread-safety: Prevents multiple sync operations from running simultaneously
    private var isSyncInProgress = false
    private var lock = NSLock()

    // Progress Stream: Uses Combine's PassthroughSubject to emit real-time updates to the UI
    private let progressSubject = PassthroughSubject<SyncProgress, Never>()
    public var progressPublisher: AnyPublisher<SyncProgress, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    public init(
        repository: SurveyRepository,
        apiService: SurveyApiService,
        devicePolicy: DevicePolicyEvaluator = FakeDevicePolicyEvaluator(),
        errorClassifier: NetworkErrorClassifier = NetworkErrorClassifier(),
        mutex: NSLock = NSLock()
    ) {
        self.repository = repository
        self.apiService = apiService
        self.devicePolicy = devicePolicy
        self.errorClassifier = errorClassifier
        self.lock = mutex
    }

    // MARK: - Public API

    /// Entry point for the synchronization process.
    /// Checks device health and ensures a singleton execution before starting the upload loop.
    public func sync() async -> SyncResult {
        let policy = devicePolicy.evaluate()
            
        // 1. Guard against poor device conditions (low battery/storage)
        if !policy.shouldSync {
            return .skipped(reason: policy.skipReason ?? "Unknown policy restriction")
        }
        
        // 2. Thread-safe lock to prevent concurrent sync sessions
        let isAlreadyRunning = lock.withLock {
            if isSyncInProgress {
                return true
            }
            isSyncInProgress = true
            return false
        }
        
        if isAlreadyRunning {
            return .alreadyRunning
        }

        let sessionId = UUID().uuidString
        
        // 3. Guarantee that the lock is released when the function finishes (success or fail)
        defer {
            lock.withLock {
                isSyncInProgress = false
            }
        }

        return await runSync(sessionId: sessionId)
    }

    // MARK: - Internal Logic

    /// The main execution loop that iterates through pending surveys and uploads them.
    private func runSync(sessionId: String) async -> SyncResult {
        // Maintenance: Cleanup old data before starting new work
        let thirtyDaysInMs: Int64 = 30 * 24 * 60 * 60 * 1000
        _ = try? await repository.pruneUploadedMedia(olderThanMs: thirtyDaysInMs)
        _ = try? await repository.pruneSyncedResponses(olderThanMs: thirtyDaysInMs)
        
        let policy = devicePolicy.evaluate()
        
        // Re-check policy inside the loop in case conditions changed during pruning
        if !policy.shouldSync {
            await log(sessionId, event: "SKIPPED", detail: policy.skipReason)
            return .skipped(reason: policy.skipReason ?? "Policy blocked sync")
        }

        // Fetch the queue
        guard let pending = try? await repository.getPendingResponses(), !pending.isEmpty else {
            return .nothingToSync
        }

        await log(sessionId, event: "STARTED", detail: "pending=\(pending.count), network=\(policy.networkType)")
        emit(.started(totalCount: pending.count))

        var succeeded: [String] = []
        var failed: [FailedItem] = []
        errorClassifier.reset()
        
        var bytesUploadedThisSession: Int64 = 0

        for (index, response) in pending.enumerated() {
            // Logic: Stop if we've exceeded the data cap for this network type
            if let maxBytes = policy.maxBytesPerSession, bytesUploadedThisSession >= maxBytes {
                let remaining = pending.count - index
                await log(sessionId, event: "BYTE_CAP_REACHED", detail: "remaining=\(remaining)")
                return .earlyTermination(
                    succeeded: succeeded,
                    failedBeforeStop: failed,
                    reason: .networkUnavailable(URLError(.backgroundSessionWasDisconnected)),
                    remainingCount: remaining
                )
            }

            // Logic: Throttle processing to save battery/reduce heat if requested by policy
            if policy.itemDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(policy.itemDelay) * 1_000_000)
            }

            emit(.itemUploading(responseId: response.id, index: index, total: pending.count))
            try? await repository.markInProgress(responseId: response.id)

            let outcome = await uploadResponse(response: response)

            switch outcome {
            case .success:
                try? await repository.markSynced(responseId: response.id, syncedAt: Int64(Date().timeIntervalSince1970 * 1000))
                errorClassifier.recordSuccess()
                succeeded.append(response.id)
                bytesUploadedThisSession += response.localStorageBytes
                await log(sessionId, responseId: response.id, event: "ITEM_SYNCED")
                emit(.itemSucceeded(responseId: response.id, index: index, total: pending.count))

            case .failure(let error):
                // Branch: Recoverable (Network/Server) vs Terminal (Client/Logic) error
                if error.isRetryable() {
                    try? await repository.markFailed(
                        responseId: response.id,
                        reason: error.userFacingMessage(),
                        retryCount: response.retryCount + 1
                    )
                } else {
                    // "Dead" items are removed from the active queue until manually fixed
                    try? await repository.markDead(
                        responseId: response.id,
                        reason: error.userFacingMessage()
                    )
                }

                errorClassifier.recordFailure(error)
                failed.append(FailedItem(responseId: response.id, error: error))
                await log(sessionId, responseId: response.id, event: "ITEM_FAILED", detail: error.userFacingMessage())
                emit(.itemFailed(responseId: response.id, error: error, index: index, total: pending.count))

                // Termination Logic: If the network is repeatedly failing, abort the whole session
                if errorClassifier.shouldAbort() {
                    let remaining = pending.count - index - 1
                    await log(sessionId, event: "EARLY_STOP", detail: "consecutive_failures=\(errorClassifier.consecutiveCount()), remaining=\(remaining)")
                    
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
        await log(sessionId, event: "COMPLETED", detail: "succeeded=\(succeeded.count), failed=\(failed.count)")
        emit(.finished(result: completed))
        return completed
    }

    /// Wraps the network call in a do-catch block and maps results to the domain Outcome.
    private func uploadResponse(response: SurveyResponse) async -> UploadOutcome {
        do {
            _ = try await apiService.uploadSurveyResponse(response: response)
            return .success
        } catch {
            return .failure(error.toSyncError())
        }
    }

    private func log(_ sessionId: String, responseId: String? = nil, event: String, detail: String? = nil) async {
        try? await repository.logSyncEvent(sessionId: sessionId, responseId: responseId, event: event, detail: detail)
    }

    private func emit(_ progress: SyncProgress) {
        progressSubject.send(progress)
    }
}
