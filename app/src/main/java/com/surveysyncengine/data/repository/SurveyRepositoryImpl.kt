package com.surveysyncengine.data.repository

import com.surveysyncengine.data.local.entity.SyncLogEntity
import com.surveysyncengine.data.local.entity.toDomain
import com.surveysyncengine.data.local.entity.toEntity
import com.surveysyncengine.domain.model.StorageStats
import com.surveysyncengine.domain.model.SurveyResponse
import com.surveysyncengine.domain.model.SyncStatus
import com.surveysyncengine.domain.repository.SurveyRepository
import com.surveysyncengine.data.local.db.dao.MediaAttachmentDao
import com.surveysyncengine.data.local.db.dao.SurveyResponseDao
import com.surveysyncengine.data.local.db.dao.SyncLogDao
import com.surveysyncengine.domain.model.DiagnosticsSnapshot
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.io.File

class SurveyRepositoryImpl(
    private val responseDao: SurveyResponseDao,
    private val attachmentDao: MediaAttachmentDao,
    private val syncLogDao: SyncLogDao,
    private val availableStorageProvider: () -> Long = { File("/data").freeSpace },
) : SurveyRepository {

    // ------------------------------------------------------------------
    // Write operations
    // ------------------------------------------------------------------

    override suspend fun saveResponse(response: SurveyResponse) {
        responseDao.insertResponse(response.toEntity())
        if (response.sections.isNotEmpty()) {
            responseDao.insertSections(response.sections.map { it.toEntity() })
        }
        if (response.attachments.isNotEmpty()) {
            responseDao.insertAttachments(response.attachments.map { it.toEntity() })
        }
    }

    override suspend fun markInProgress(responseId: String) {
        responseDao.markInProgress(responseId)
    }

    override suspend fun markSynced(responseId: String, syncedAt: Long) {
        responseDao.markSynced(responseId, syncedAt)
    }

    override suspend fun markFailed(responseId: String, reason: String, retryCount: Int) {
        responseDao.markFailed(responseId, reason, retryCount)
    }

    override suspend fun markDead(responseId: String, reason: String) {
        responseDao.markDead(responseId, reason)
    }

    override suspend fun resetStuckInProgress() {
        responseDao.resetStuckInProgress()
    }

    override suspend fun markAttachmentUploaded(attachmentId: String, serverUrl: String) {
        attachmentDao.markUploaded(attachmentId, serverUrl)
    }

    override suspend fun markAttachmentFailed(attachmentId: String) {
        attachmentDao.markFailed(attachmentId)
    }

    // ------------------------------------------------------------------
    // Read operations
    // ------------------------------------------------------------------

    override suspend fun getPendingResponses(): List<SurveyResponse> =
        responseDao.getPendingAggregates().map { it.toDomain() }

    override suspend fun getResponseById(id: String): SurveyResponse? =
        responseDao.getAggregateById(id)?.toDomain()

    override fun observeAllResponses(): Flow<List<SurveyResponse>> =
        responseDao.observeAll().map { list -> list.map { it.toDomain() } }

    override fun observeByStatus(status: SyncStatus): Flow<List<SurveyResponse>> =
        responseDao.observeByStatus(status).map { list -> list.map { it.toDomain() } }

    // ------------------------------------------------------------------
    // Storage management
    // ------------------------------------------------------------------

    override suspend fun getStorageStats(): StorageStats = StorageStats(
        totalPendingBytes = responseDao.totalPendingAttachmentBytes(),
        totalSyncedBytes = responseDao.totalSyncedAttachmentBytes(),
        availableDeviceBytes = availableStorageProvider(),
        attachmentCount = responseDao.attachmentCount(),
    )

    override suspend fun pruneUploadedMedia(olderThanMs: Long): Long {
        val cutoff = System.currentTimeMillis() - olderThanMs
        val paths = responseDao.getUploadedAttachmentPaths(cutoff)
        var freedBytes = 0L
        paths.forEach { path ->
            val file = File(path)
            if (file.exists()) {
                freedBytes += file.length()
                file.delete()
            }
        }
        responseDao.deleteUploadedAttachmentsOlderThan(cutoff)
        return freedBytes
    }

    override suspend fun pruneSyncedResponses(olderThanMs: Long): Int {
        val cutoff = System.currentTimeMillis() - olderThanMs
        return responseDao.deleteSyncedOlderThan(cutoff)
    }

    // ------------------------------------------------------------------
    // Diagnostics
    // ------------------------------------------------------------------

    override suspend fun getDiagnosticsSnapshot(): DiagnosticsSnapshot {
        val recentLogs = syncLogDao.getRecent(20)
        return DiagnosticsSnapshot(
            pendingCount = responseDao.countByStatus(SyncStatus.PENDING),
            failedCount = responseDao.countByStatus(SyncStatus.FAILED),
            syncedCount = responseDao.countByStatus(SyncStatus.SYNCED),
            oldestPendingAgeMs = responseDao.oldestPendingCreatedAt()
                ?.let { System.currentTimeMillis() - it },
            totalStorageBytes = responseDao.totalPendingAttachmentBytes() +
                    responseDao.totalSyncedAttachmentBytes(),
            recentSyncErrors = recentLogs
                .filter { it.event == "ITEM_FAILED" || it.event == "EARLY_STOP" }
                .mapNotNull { it.detail },
            deviceStorageAvailableBytes = availableStorageProvider(),
        )
    }

    // ------------------------------------------------------------------
    // Logging helpers (called by SyncEngine)
    // ------------------------------------------------------------------

    override suspend fun logSyncEvent(
        sessionId: String,
        responseId: String? ,
        event: String,
        detail: String?,
    ) {
        syncLogDao.insert(
            SyncLogEntity(
                sessionId = sessionId,
                responseId = responseId,
                event = event,
                detail = detail,
            )
        )
    }
}
