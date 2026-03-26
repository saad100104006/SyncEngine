package com.android.surveysyncengine

import com.surveysyncengine.domain.repository.SurveyRepository
import com.surveysyncengine.domain.model.DiagnosticsSnapshot
import com.surveysyncengine.domain.model.StorageStats
import com.surveysyncengine.domain.model.SurveyResponse
import com.surveysyncengine.domain.model.SyncStatus
import com.surveysyncengine.domain.model.UploadStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update

// ---------------------------------------------------------------------------
// FakeSurveyRepository — pure in-memory repository for fast unit tests.
// No Room, no coroutine test rules for DB, no Android test runner needed.
//
// Exposes inspection properties so tests can assert on internal state:
//   fakeRepo.statusOf("resp-1") == SyncStatus.SYNCED
// ---------------------------------------------------------------------------
open class FakeSurveyRepository : SurveyRepository {

    private val _responses = MutableStateFlow<Map<String, SurveyResponse>>(emptyMap())

    // Inspection helpers
    fun statusOf(id: String): SyncStatus? = _responses.value[id]?.status
    fun retryCountOf(id: String): Int? = _responses.value[id]?.retryCount
    fun failureReasonOf(id: String): String? = _responses.value[id]?.failureReason
    fun allResponses(): List<SurveyResponse> = _responses.value.values.toList()
    fun syncedIds(): List<String> = _responses.value.values
        .filter { it.status == SyncStatus.SYNCED }.map { it.id }
    fun failedIds(): List<String> = _responses.value.values
        .filter { it.status == SyncStatus.FAILED }.map { it.id }
    fun pendingIds(): List<String> = _responses.value.values
        .filter { it.status == SyncStatus.PENDING }.map { it.id }

    val loggedEvents = mutableListOf<Pair<String, String?>>() // (event, detail)

    override suspend fun saveResponse(response: SurveyResponse) {
        _responses.update { it + (response.id to response) }
    }

    override suspend fun markInProgress(responseId: String) = update(responseId) {
        copy(status = SyncStatus.IN_PROGRESS)
    }

    override suspend fun markSynced(responseId: String, syncedAt: Long) = update(responseId) {
        copy(status = SyncStatus.SYNCED, syncedAt = syncedAt, failureReason = null)
    }

    override suspend fun markFailed(responseId: String, reason: String, retryCount: Int) =
        update(responseId) {
            copy(status = SyncStatus.FAILED, failureReason = reason, retryCount = retryCount)
        }

    override suspend fun markDead(responseId: String, reason: String) =
        update(responseId) {
            copy(status = SyncStatus.DEAD, failureReason = reason)
        }

    fun deadIds(): List<String> = _responses.value.values
        .filter { it.status == SyncStatus.DEAD }.map { it.id }

    override suspend fun resetStuckInProgress() {
        _responses.update { map ->
            map.mapValues { (_, v) ->
                if (v.status == SyncStatus.IN_PROGRESS) v.copy(status = SyncStatus.PENDING) else v
            }
        }
    }

    override suspend fun markAttachmentUploaded(attachmentId: String, serverUrl: String) {
        _responses.update { map ->
            map.mapValues { (_, response) ->
                val updated = response.attachments.map { att ->
                    if (att.id == attachmentId) att.copy(uploadStatus = UploadStatus.UPLOADED, serverUrl = serverUrl)
                    else att
                }
                response.copy(attachments = updated)
            }
        }
    }

    override suspend fun markAttachmentFailed(attachmentId: String) {
        _responses.update { map ->
            map.mapValues { (_, response) ->
                val updated = response.attachments.map { att ->
                    if (att.id == attachmentId) att.copy(uploadStatus = UploadStatus.FAILED)
                    else att
                }
                response.copy(attachments = updated)
            }
        }
    }

    override suspend fun getPendingResponses(): List<SurveyResponse> =
        _responses.value.values
            .filter { it.status == SyncStatus.PENDING || it.status == SyncStatus.FAILED }
            .sortedBy { it.createdAt }

    override suspend fun getResponseById(id: String): SurveyResponse? =
        _responses.value[id]

    override fun observeAllResponses(): Flow<List<SurveyResponse>> =
        _responses.map { it.values.sortedByDescending { r -> r.createdAt } }

    override fun observeByStatus(status: SyncStatus): Flow<List<SurveyResponse>> =
        _responses.map { map -> map.values.filter { it.status == status }.sortedByDescending { it.createdAt } }

    override suspend fun getStorageStats(): StorageStats = StorageStats(
        totalPendingBytes = _responses.value.values
            .filter { it.status != SyncStatus.SYNCED }
            .sumOf { it.localStorageBytes },
        totalSyncedBytes = _responses.value.values
            .filter { it.status == SyncStatus.SYNCED }
            .sumOf { it.localStorageBytes },
        availableDeviceBytes = 4L * 1024 * 1024 * 1024,
        attachmentCount = _responses.value.values.sumOf { it.attachments.size },
    )

    override suspend fun pruneUploadedMedia(olderThanMs: Long): Long = 0L
    override suspend fun pruneSyncedResponses(olderThanMs: Long): Int = 0

    override suspend fun getDiagnosticsSnapshot() = DiagnosticsSnapshot(
        pendingCount = pendingIds().size,
        failedCount = failedIds().size,
        syncedCount = syncedIds().size,
        oldestPendingAgeMs = null,
        totalStorageBytes = 0L,
        recentSyncErrors = loggedEvents.filter { it.first == "ITEM_FAILED" }.mapNotNull { it.second },
        deviceStorageAvailableBytes = 4L * 1024 * 1024 * 1024,
    )

    // SurveyRepositoryImpl-specific extension (sync logging)
    override suspend fun logSyncEvent(sessionId: String, responseId: String?, event: String, detail: String?) {
        loggedEvents.add(event to detail)
    }

    // ------------------------------------------------------------------
    private fun update(id: String, transform: SurveyResponse.() -> SurveyResponse) {
        _responses.update { map ->
            val existing = map[id] ?: return@update map
            map + (id to existing.transform())
        }
    }
}
