package com.surveysyncengine.domain.repository

import com.surveysyncengine.domain.model.DiagnosticsSnapshot
import com.surveysyncengine.domain.model.StorageStats
import com.surveysyncengine.domain.model.SurveyResponse
import com.surveysyncengine.domain.model.SyncStatus
import kotlinx.coroutines.flow.Flow

interface SurveyRepository {

    // ------------------------------------------------------------------
    // Write operations
    // ------------------------------------------------------------------

    /** Persist a newly completed survey response locally. */
    suspend fun saveResponse(response: SurveyResponse)

    /** Atomically flip status to IN_PROGRESS to prevent double-pickup. */
    suspend fun markInProgress(responseId: String)

    /** Mark a response as successfully uploaded. */
    suspend fun markSynced(responseId: String, syncedAt: Long = System.currentTimeMillis())

    /**
     * Mark a response as FAILED and record the reason + bump retry count.
     * Use for transient failures (network down, 5xx). Response WILL be retried.
     */
    suspend fun markFailed(responseId: String, reason: String, retryCount: Int)

    /**
     * Mark a response as DEAD — permanently rejected by the server (4xx).
     * The response will NOT be picked up by getPendingResponses() on the next sync.
     * Data correction or operator intervention is required before re-submission.
     */
    suspend fun markDead(responseId: String, reason: String)

    /**
     * Reset any IN_PROGRESS responses back to PENDING.
     * Called on app start to recover from a crash mid-sync.
     */
    suspend fun resetStuckInProgress()

    /** Update a media attachment's upload status and server URL after upload. */
    suspend fun markAttachmentUploaded(attachmentId: String, serverUrl: String)

    /** Mark attachment upload as failed. */
    suspend fun markAttachmentFailed(attachmentId: String)

    // ------------------------------------------------------------------
    // Read operations
    // ------------------------------------------------------------------

    /** All responses with status PENDING or FAILED, ordered by createdAt ASC. */
    suspend fun getPendingResponses(): List<SurveyResponse>

    /** A single response by ID (includes sections + attachments). */
    suspend fun getResponseById(id: String): SurveyResponse?

    /** Observe all responses — for UI layers that want live updates. */
    fun observeAllResponses(): Flow<List<SurveyResponse>>

    /** Observe responses filtered by status. */
    fun observeByStatus(status: SyncStatus): Flow<List<SurveyResponse>>

    // ------------------------------------------------------------------
    // Storage management
    // ------------------------------------------------------------------

    /** Current storage usage snapshot. */
    suspend fun getStorageStats(): StorageStats

    /**
     * Delete local media files for SYNCED responses older than [olderThanMs].
     * Returns the number of bytes freed.
     */
    suspend fun pruneUploadedMedia(olderThanMs: Long): Long

    /**
     * Hard-delete SYNCED responses (and their sections/attachments) older
     * than the retention window. Keeps the DB lean on long-lived devices.
     */
    suspend fun pruneSyncedResponses(olderThanMs: Long): Int

    // ------------------------------------------------------------------
    // Diagnostics
    // ------------------------------------------------------------------

    /** Snapshot for support / remote troubleshooting. */
    suspend fun getDiagnosticsSnapshot(): DiagnosticsSnapshot

    // ------------------------------------------------------------------
    // Sync session logging
    // Called by SyncEngine — lives on the interface so the engine depends
    // only on domain and never needs to import SurveyRepositoryImpl.
    // ------------------------------------------------------------------
    suspend fun logSyncEvent(
        sessionId: String,
        responseId: String? = null,
        event: String,
        detail: String? = null,
    )
}


