package com.surveysyncengine.sync

import com.surveysyncengine.domain.error.SyncError
import com.surveysyncengine.domain.error.toSyncError
import com.surveysyncengine.domain.model.SurveyResponse
import com.surveysyncengine.domain.api.SurveyApiService
import com.survey.sync.domain.repository.SurveyRepository
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.sync.Mutex
import java.util.UUID


open class SyncEngine(
    private val repository: SurveyRepository,           // domain interface ✓
    private val apiService: SurveyApiService,            // domain interface ✓
    private val devicePolicy: DevicePolicyEvaluator = FakeDevicePolicyEvaluator(),
    private val errorClassifier: NetworkErrorClassifier = NetworkErrorClassifier(),
    private val mutex: Mutex = Mutex(),
) {
    companion object {
        // Media files for uploaded responses are deleted after 3 days.
        // This gives agents a short recovery window if a file needs re-inspection,
        // while bounding storage growth on 16–32 GB devices.
        private const val MEDIA_RETENTION_MS = 3L * 24 * 60 * 60 * 1000

        // Synced response records (metadata only, no files) are purged after 30 days.
        // Keeping records longer enables diagnostics and audit without consuming
        // meaningful storage — each record without attachments is a few KB at most.
        private const val RECORD_RETENTION_MS = 30L * 24 * 60 * 60 * 1000
    }
    // Bonus: progress stream for UI layers
    private val _progress = MutableSharedFlow<SyncProgress>(extraBufferCapacity = 64)
    val progress: SharedFlow<SyncProgress> = _progress.asSharedFlow()

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    /**
     * Attempt to sync all pending responses.
     *
     * This function is safe to call from any coroutine context.
     * It returns immediately with [SyncResult.AlreadyRunning] if a sync
     * is already in flight — the caller does NOT need to debounce.
     */
    open suspend fun sync(): SyncResult {
        // Scenario 4: concurrent sync prevention
        if (!mutex.tryLock()) return SyncResult.AlreadyRunning

        val sessionId = UUID.randomUUID().toString()
        return try {
            runSync(sessionId)
        } finally {
            mutex.unlock()
        }
    }

    // ------------------------------------------------------------------
    // Internal
    // ------------------------------------------------------------------

    private suspend fun runSync(sessionId: String): SyncResult {
        // Device policy check (bonus: battery / storage / network awareness)
        val policy = devicePolicy.evaluate()
        if (!policy.shouldSync) {
            log(sessionId, event = "SKIPPED", detail = policy.skipReason)
            return SyncResult.SkippedByPolicy(policy.skipReason ?: "Policy blocked sync")
        }

        // Scenario 1 — storage growth management.
        // Prune media files and synced records that are older than the retention
        // window before every sync session. Running this here (not post-sync) means
        // pruning still fires even if the session ends in EarlyTermination, which is
        // the case most likely to leave stale files accumulating on a full device.
        pruneStaleData(sessionId)

        val pending = repository.getPendingResponses()
        if (pending.isEmpty()) {
            return SyncResult.NothingToSync
        }

        log(sessionId, event = "STARTED", detail = "pending=${pending.size}, network=${policy.networkType}")
        emit(SyncProgress.Started(pending.size))

        val succeeded = mutableListOf<String>()
        val failed = mutableListOf<FailedItem>()
        errorClassifier.reset()

        var bytesUploadedThisSession = 0L

        for ((index, response) in pending.withIndex()) {
            // Bonus: per-session byte cap (metered network throttle)
            if (policy.maxBytesPerSession != null &&
                bytesUploadedThisSession >= policy.maxBytesPerSession
            ) {
                val remaining = pending.size - index
                log(sessionId, event = "BYTE_CAP_REACHED", detail = "remaining=$remaining")
                return SyncResult.EarlyTermination(
                    succeeded = succeeded,
                    failedBeforeStop = failed,
                    reason = SyncError.NetworkUnavailable(
                        RuntimeException("Metered network byte cap reached")
                    ),
                    remainingCount = remaining,
                )
            }

            // Bonus: throttle between items on low battery
            if (policy.itemDelayMs > 0) delay(policy.itemDelayMs)

            emit(SyncProgress.ItemUploading(response.id, index, pending.size))
            repository.markInProgress(response.id)

            val result = uploadResponse(sessionId, response)

            when (result) {
                is UploadOutcome.Success -> {
                    repository.markSynced(response.id)
                    errorClassifier.recordSuccess()
                    succeeded.add(response.id)
                    bytesUploadedThisSession += response.localStorageBytes
                    log(sessionId, response.id, "ITEM_SYNCED")
                    emit(SyncProgress.ItemSucceeded(response.id, index, pending.size))
                }

                is UploadOutcome.Failure -> {
                    val error = result.error

                    // This is the core distinction the spec requires:
                    //   isRetryable() = true  → transient (network down, 5xx) → markFailed → retried next sync
                    //   isRetryable() = false → permanent (4xx bad payload)   → markDead   → never retried
                    if (error.isRetryable()) {
                        repository.markFailed(
                            responseId = response.id,
                            reason = error.userFacingMessage(),
                            retryCount = response.retryCount + 1,
                        )
                    } else {
                        repository.markDead(
                            responseId = response.id,
                            reason = error.userFacingMessage(),
                        )
                    }

                    errorClassifier.recordFailure(error)
                    failed.add(FailedItem(response.id, error))
                    log(sessionId, response.id, "ITEM_FAILED", error.userFacingMessage())
                    emit(SyncProgress.ItemFailed(response.id, error, index, pending.size))

                    // Scenario 3: abort early on repeated network failures
                    if (errorClassifier.shouldAbort()) {
                        val remaining = pending.size - index - 1
                        log(sessionId, event = "EARLY_STOP",
                            detail = "consecutive_network_failures=${errorClassifier.consecutiveCount()}, remaining=$remaining")
                        val termination = SyncResult.EarlyTermination(
                            succeeded = succeeded,
                            failedBeforeStop = failed,
                            reason = error,
                            remainingCount = remaining,
                        )
                        emit(SyncProgress.Finished(termination))
                        return termination
                    }
                }
            }
        }

        val completed = SyncResult.Completed(succeeded, failed)
        log(sessionId, event = "COMPLETED",
            detail = "succeeded=${succeeded.size}, failed=${failed.size}")
        emit(SyncProgress.Finished(completed))
        return completed
    }

    // ------------------------------------------------------------------
    // Storage management
    // ------------------------------------------------------------------

    private suspend fun pruneStaleData(sessionId: String) {
        try {
            val mediaFreed = repository.pruneUploadedMedia(MEDIA_RETENTION_MS)
            val recordsDeleted = repository.pruneSyncedResponses(RECORD_RETENTION_MS)
            if (mediaFreed > 0 || recordsDeleted > 0) {
                log(
                    sessionId,
                    event = "PRUNED",
                    detail = "media_freed_bytes=$mediaFreed, records_deleted=$recordsDeleted",
                )
            }
        } catch (e: Throwable) {
            // Pruning failure must never block a sync session — log and continue
            log(sessionId, event = "PRUNE_ERROR", detail = e.message)
        }
    }

    private suspend fun uploadResponse(
        sessionId: String,
        response: SurveyResponse,
    ): UploadOutcome {
        return try {
            apiService.uploadSurveyResponse(response)
            UploadOutcome.Success
        } catch (e: Throwable) {
            UploadOutcome.Failure(e.toSyncError())
        }
    }

    private suspend fun log(
        sessionId: String,
        responseId: String? = null,
        event: String,
        detail: String? = null,
    ) {
        repository.logSyncEvent(sessionId, responseId, event, detail)
    }

    private fun emit(progress: SyncProgress) {
        _progress.tryEmit(progress)
    }
}

// Internal sealed type — keeps success/failure explicit without nulls
private sealed interface UploadOutcome {
    object Success : UploadOutcome
    data class Failure(val error: SyncError) : UploadOutcome
}
