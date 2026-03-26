package com.surveysyncengine.data.local.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.surveysyncengine.data.local.entity.MediaAttachmentEntity
import com.surveysyncengine.data.local.entity.ResponseSectionEntity
import com.surveysyncengine.data.local.entity.SurveyResponseAggregate
import com.surveysyncengine.data.local.entity.SurveyResponseEntity
import com.surveysyncengine.domain.model.SyncStatus
import kotlinx.coroutines.flow.Flow

// ---------------------------------------------------------------------------
// SurveyResponseDao
// ---------------------------------------------------------------------------

@Dao
interface SurveyResponseDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertResponse(entity: SurveyResponseEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertSections(sections: List<ResponseSectionEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAttachments(attachments: List<MediaAttachmentEntity>)

    // ------------------------------------------------------------------
    // Status transitions — fine-grained updates rather than full re-insert
    // ------------------------------------------------------------------

    @Query("UPDATE survey_responses SET status = 'IN_PROGRESS' WHERE id = :id")
    suspend fun markInProgress(id: String)

    @Query("""
        UPDATE survey_responses 
        SET status = 'SYNCED', syncedAt = :syncedAt, failureReason = NULL
        WHERE id = :id
    """)
    suspend fun markSynced(id: String, syncedAt: Long)

    @Query("""
        UPDATE survey_responses 
        SET status = 'FAILED', failureReason = :reason, retryCount = :retryCount
        WHERE id = :id
    """)
    suspend fun markFailed(id: String, reason: String, retryCount: Int)

    /**
     * Permanently reject a response — will not be returned by getPendingAggregates().
     * Used for 4xx errors where retrying the same payload will always fail.
     */
    @Query("""
        UPDATE survey_responses
        SET status = 'DEAD', failureReason = :reason
        WHERE id = :id
    """)
    suspend fun markDead(id: String, reason: String)

    /** Crash recovery: IN_PROGRESS → PENDING on app restart. */
    @Query("UPDATE survey_responses SET status = 'PENDING' WHERE status = 'IN_PROGRESS'")
    suspend fun resetStuckInProgress()

    // ------------------------------------------------------------------
    // Queries
    // ------------------------------------------------------------------

    @Transaction
    @Query("""
        SELECT * FROM survey_responses 
        WHERE status IN ('PENDING', 'FAILED')
        ORDER BY createdAt ASC
    """)
    suspend fun getPendingAggregates(): List<SurveyResponseAggregate>

    @Transaction
    @Query("SELECT * FROM survey_responses WHERE id = :id")
    suspend fun getAggregateById(id: String): SurveyResponseAggregate?

    @Transaction
    @Query("SELECT * FROM survey_responses ORDER BY createdAt DESC")
    fun observeAll(): Flow<List<SurveyResponseAggregate>>

    @Transaction
    @Query("SELECT * FROM survey_responses WHERE status = :status ORDER BY createdAt DESC")
    fun observeByStatus(status: SyncStatus): Flow<List<SurveyResponseAggregate>>

    // ------------------------------------------------------------------
    // Storage / diagnostics
    // ------------------------------------------------------------------

    @Query("SELECT COALESCE(SUM(sizeBytes), 0) FROM media_attachments WHERE uploadStatus = 'PENDING'")
    suspend fun totalPendingAttachmentBytes(): Long

    @Query("SELECT COALESCE(SUM(sizeBytes), 0) FROM media_attachments WHERE uploadStatus = 'UPLOADED'")
    suspend fun totalSyncedAttachmentBytes(): Long

    @Query("SELECT COUNT(*) FROM media_attachments")
    suspend fun attachmentCount(): Int

    @Query("SELECT MIN(createdAt) FROM survey_responses WHERE status IN ('PENDING', 'FAILED')")
    suspend fun oldestPendingCreatedAt(): Long?

    @Query("SELECT COUNT(*) FROM survey_responses WHERE status = :status")
    suspend fun countByStatus(status: SyncStatus): Int

    // ------------------------------------------------------------------
    // Pruning
    // ------------------------------------------------------------------

    @Query("""
        DELETE FROM survey_responses 
        WHERE status = 'SYNCED' AND syncedAt < :olderThan
    """)
    suspend fun deleteSyncedOlderThan(olderThan: Long): Int

    @Query("""
        SELECT localFilePath FROM media_attachments 
        WHERE uploadStatus = 'UPLOADED' 
        AND surveyResponseId IN (
            SELECT id FROM survey_responses WHERE syncedAt < :olderThan
        )
    """)
    suspend fun getUploadedAttachmentPaths(olderThan: Long): List<String>

    @Query("""
        DELETE FROM media_attachments 
        WHERE uploadStatus = 'UPLOADED' 
        AND surveyResponseId IN (
            SELECT id FROM survey_responses WHERE syncedAt < :olderThan
        )
    """)
    suspend fun deleteUploadedAttachmentsOlderThan(olderThan: Long)
}
