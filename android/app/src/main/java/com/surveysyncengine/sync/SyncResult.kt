package com.surveysyncengine.sync

import com.surveysyncengine.domain.error.SyncError

// ---------------------------------------------------------------------------
// SyncResult — exhaustive outcome model returned by SyncEngine.sync().
// Every caller can pattern-match to know exactly what happened.
// ---------------------------------------------------------------------------
sealed class SyncResult {

    /**
     * All pending responses were attempted.
     * [succeeded] — IDs confirmed by server.
     * [failed]    — IDs with their specific error; won't be re-uploaded next sync.
     */
    data class Completed(
        val succeeded: List<String>,
        val failed: List<FailedItem>,
    ) : SyncResult() {
        val hasPartialFailure: Boolean get() = failed.isNotEmpty()
    }

    /**
     * Sync stopped before processing every pending response because the
     * network appears to be down. Remaining items stay PENDING.
     * [reason] explains the triggering error.
     */
    data class EarlyTermination(
        val succeeded: List<String>,
        val failedBeforeStop: List<FailedItem>,
        val reason: SyncError,
        val remainingCount: Int,
    ) : SyncResult()

    /**
     * A sync was already in flight when this call arrived.
     * No work was done; the caller should observe the in-flight sync instead.
     */
    object AlreadyRunning : SyncResult()

    /** No PENDING or FAILED responses exist — nothing to do. */
    object NothingToSync : SyncResult()

    /**
     * Sync was skipped due to device conditions (low battery, low storage,
     * metered network with large payloads, etc.).
     */
    data class SkippedByPolicy(val reason: String) : SyncResult()
}

data class FailedItem(
    val responseId: String,
    val error: SyncError,
)

// ---------------------------------------------------------------------------
// SyncProgress — emitted via Flow for UI progress reporting (bonus feature).
// ---------------------------------------------------------------------------
sealed class SyncProgress {
    data class Started(val totalCount: Int) : SyncProgress()
    data class ItemUploading(val responseId: String, val index: Int, val total: Int) : SyncProgress()
    data class ItemSucceeded(val responseId: String, val index: Int, val total: Int) : SyncProgress()
    data class ItemFailed(val responseId: String, val error: SyncError, val index: Int, val total: Int) : SyncProgress()
    data class Finished(val result: SyncResult) : SyncProgress()
}
