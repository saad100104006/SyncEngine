package com.surveysyncengine.domain.model

/**
 * Point-in-time snapshot of sync engine state for remote diagnostics.
 *
 * Produced by [SurveyRepository.getDiagnosticsSnapshot] and intended to be
 * serialised to JSON and uploaded to a support endpoint when a field agent
 * reports a sync problem. Support staff can read this without physical access
 * to the device.
 *
 * Key diagnostic patterns:
 * - [failedCount] > 0 and [oldestPendingAgeMs] > 24 h → responses are stuck,
 *   likely a persistent server rejection or connectivity blackout.
 * - [recentSyncErrors] all contain "400" or "422" → bad payload; data correction
 *   needed, retrying will not help.
 * - [deviceStorageAvailableBytes] < 50 MB → storage pressure may be blocking
 *   new survey saves or triggering the policy skip in [SyncEngine].
 *
 * @property pendingCount Number of responses with status PENDING — saved locally,
 *   never successfully uploaded.
 * @property failedCount Number of responses with status FAILED — at least one
 *   upload attempt made, all transient failures (network / 5xx), will be retried.
 * @property syncedCount Number of responses confirmed received by the server.
 *   Useful as a sanity check that sync has worked at least once this session.
 * @property oldestPendingAgeMs Milliseconds since the oldest PENDING or FAILED
 *   response was created, or null if the queue is empty. A large value (> 24 h)
 *   indicates responses have been stuck across multiple sync sessions.
 * @property totalStorageBytes Total bytes consumed by all attachment files
 *   (pending + uploaded) currently tracked in the database.
 * @property recentSyncErrors The last N error messages recorded in the sync log,
 *   most recent first. Includes both per-item failures and session-level events
 *   such as EARLY_STOP. N is determined by the repository implementation (default 20).
 * @property deviceStorageAvailableBytes Free bytes remaining on the device's
 *   data partition at snapshot time. Used to rule out storage exhaustion as the
 *   cause of failures and to verify the 50 MB minimum required for sync to proceed.
 */

data class DiagnosticsSnapshot(
    val pendingCount: Int,
    val failedCount: Int,
    val syncedCount: Int,
    val oldestPendingAgeMs: Long?,
    val totalStorageBytes: Long,
    val recentSyncErrors: List<String>,   // last N error messages
    val deviceStorageAvailableBytes: Long,
)